Describe 'run-trigger-evals Execute mode' -Tag 'Unit' {
    BeforeAll {
        $script:scriptPath = Join-Path $PSScriptRoot (
            '../skills/agent-evals/scripts/run-trigger-evals.ps1'
        )

        $script:tempRoot = Join-Path ([IO.Path]::GetTempPath()) (
            'trigger-eval-tests-{0}' -f [guid]::NewGuid().ToString('N')
        )
        $script:skillRoot = Join-Path $script:tempRoot 'skills'
        $script:workDir = Join-Path $script:tempRoot 'work'
        New-Item -ItemType Directory -Path $script:workDir -Force | Out-Null

        foreach ($name in 'alpha-skill', 'beta-skill')
        {
            $dir = Join-Path $script:skillRoot $name
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $body = @"
---
name: $name
description: Use this skill for $name work.
---

# $name
"@
            Set-Content -LiteralPath (Join-Path $dir 'SKILL.md') -Value $body -Encoding utf8
        }

        # Structurally valid: unique ids, non-empty text, both splits carry a
        # positive and a negative. Test-QuerySet warns about the small counts but
        # only throws on structural problems, so this is enough to drive Execute.
        $script:queryFile = Join-Path $script:tempRoot 'queries.json'
        $queries = @(
            [pscustomobject]@{ id = 'pos-01'; query = 'help me with alpha-skill work'; should_trigger = $true; split = 'train' }
            [pscustomobject]@{ id = 'neg-01'; query = 'what is the weather'; should_trigger = $false; split = 'train' }
            [pscustomobject]@{ id = 'pos-02'; query = 'more alpha-skill work please'; should_trigger = $true; split = 'validation' }
            [pscustomobject]@{ id = 'neg-02'; query = 'tell me a joke'; should_trigger = $false; split = 'validation' }
        )
        Set-Content -LiteralPath $script:queryFile -Value ($queries | ConvertTo-Json) -Encoding utf8

        # A first draft of this test reached the LIVE backend: the script's own
        # Get-Command probe auto-loaded the real ShellPilot, whose exported
        # Invoke-Shp then replaced the stub in the global function table.
        # Removing the module and defining the stub last keeps resolution on the
        # stub - and the command is found, so auto-loading never triggers.
        # Do NOT reach for $PSModuleAutoLoadingPreference = 'None' here: it also
        # stops Microsoft.PowerShell.Management loading, so the harness loses
        # Join-Path and Get-ChildItem and every call fails for the wrong reason.
        # Held as a scriptblock so Invoke-Harness can re-assert it before every
        # run, whatever the previous run left in the function table.
        $script:modernShpStub = {
            [CmdletBinding()]
            param(
                [string] $Prompt,
                [string] $Model,
                [object] $Temperature,
                [double] $MaxBudgetUSD,
                [int] $TimeoutSec,
                [switch] $DisableUserTools,
                [switch] $DisableBrowsing,
                [switch] $DisableFileAccess,
                [switch] $DisableTerminal,
                [switch] $DisableUserPrompts,
                [switch] $DisableTodoList
            )

            $global:ShpStubCalls.Add([pscustomobject]@{
                    Temperature = $Temperature
                    HadTemp     = ($null -ne $Temperature)
                })

            [pscustomobject]@{ Content = 'SELECTED: none'; CostUSD = 0.0 }
        }

        # Execute mode also calls Clear-ShpChat between prompts on the sequential
        # path. Leaving it unstubbed makes PowerShell auto-load the INSTALLED
        # ShellPilot to resolve it, and that import then overwrites the Invoke-Shp
        # stub above - which is how this test first reached the live backend, and
        # later failed against an installed build too old to accept -Temperature.
        # Every ShellPilot command the harness touches has to be stubbed. The
        # counter is what proves the batch path does not reset a conversation it
        # never uses.
        $script:clearShpStub = { $global:ShpClearCalls++ }

        # Batch dispatch: one call for the whole sweep, results emitted in
        # COMPLETION order. The stub reverses the input deliberately, so a
        # harness that correlated replies by position would write every answer
        # to the wrong file and the identity test would fail loudly.
        $script:batchShpStub = {
            [CmdletBinding()]
            param(
                [Parameter(ValueFromPipeline)]
                [object[]] $Prompt,
                [int] $ThrottleLimit,
                [string] $Model,
                [object] $Temperature,
                [double] $MaxBudgetUSD,
                [int] $TimeoutSec,
                [switch] $DisableUserTools,
                [switch] $DisableBrowsing,
                [switch] $DisableFileAccess,
                [switch] $DisableTerminal,
                [switch] $DisableTodoList
            )

            begin
            {
                $items = [System.Collections.Generic.List[object]]::new()
            }

            process
            {
                foreach ($p in $Prompt) { $items.Add($p) }
            }

            end
            {
                $global:ShpBatchCalls.Add([pscustomobject]@{
                        ThrottleLimit = $ThrottleLimit
                        Model         = $Model
                        Temperature   = $Temperature
                        HadTemp       = ($null -ne $Temperature)
                        Ids           = @($items | ForEach-Object { $_.Id })
                    })

                $ordered = @($items)
                [array]::Reverse($ordered)

                foreach ($item in $ordered)
                {
                    $failing = $global:ShpBatchFailIds -contains $item.Id

                    [pscustomobject]@{
                        PSTypeName = 'ShellPilot.BatchResult'
                        Index      = $items.IndexOf($item)
                        Id         = $item.Id
                        Success    = (-not $failing)
                        Content    = $(if ($failing) { $null } else { "SELECTED: none`nanswered:$($item.Id)" })
                        CostUSD    = $(if ($failing) { $null } else { 0.25 })
                        Error      = $(if ($failing) { 'simulated backend failure' } else { $null })
                    }
                }
            }
        }

        # A real module on disk, not a bare function, standing in for the stale
        # install that prompted the guard: ShellPilot 0.4.0-preview0003 reports
        # version 0.4.0 and exposes no -Temperature, so a minimum-version check
        # would have passed it. Being a module is what gives Get-Command a
        # Version, a Prerelease and a ModuleBase to name in the failure.
        $script:staleModuleBase = Join-Path (Join-Path $script:tempRoot 'stale-modules/ShellPilot') '0.4.0'
        New-Item -ItemType Directory -Path $script:staleModuleBase -Force | Out-Null
        $script:staleManifest = Join-Path $script:staleModuleBase 'ShellPilot.psd1'

        Set-Content -LiteralPath (Join-Path $script:staleModuleBase 'ShellPilot.psm1') -Encoding utf8 -Value @'
function Invoke-Shp
{
    [CmdletBinding()]
    param(
        [string] $Prompt,
        [string] $Model,
        [double] $MaxBudgetUSD,
        [int] $TimeoutSec,
        [switch] $DisableUserTools,
        [switch] $DisableBrowsing,
        [switch] $DisableFileAccess,
        [switch] $DisableTerminal,
        [switch] $DisableUserPrompts,
        [switch] $DisableTodoList
    )

    $global:ShpStubCalls.Add([pscustomobject]@{ Temperature = $null; HadTemp = $false })

    [pscustomobject]@{ Content = 'SELECTED: none'; CostUSD = 0.0 }
}

# A batch command without -Temperature. The guard has to notice that the
# DISPATCH command lacks the parameter, not that Invoke-Shp happens to have it.
function Invoke-ShpBatch
{
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [object[]] $Prompt,
        [int] $ThrottleLimit,
        [string] $Model,
        [double] $MaxBudgetUSD,
        [int] $TimeoutSec,
        [switch] $DisableUserTools,
        [switch] $DisableBrowsing,
        [switch] $DisableFileAccess,
        [switch] $DisableTerminal,
        [switch] $DisableTodoList
    )

    process
    {
        foreach ($p in $Prompt)
        {
            $global:ShpStubCalls.Add([pscustomobject]@{ Temperature = $null; HadTemp = $false })

            [pscustomobject]@{ Id = $p.Id; Success = $true; Content = 'SELECTED: none'; CostUSD = 0.0; Error = $null }
        }
    }
}

function Clear-ShpChat { }
'@

        Set-Content -LiteralPath $script:staleManifest -Encoding utf8 -Value @"
@{
    RootModule        = 'ShellPilot.psm1'
    ModuleVersion     = '0.4.0'
    GUID              = '$([guid]::NewGuid())'
    Author            = 'trigger-eval tests'
    FunctionsToExport = @('Invoke-Shp', 'Invoke-ShpBatch', 'Clear-ShpChat')
    PrivateData       = @{ PSData = @{ Prerelease = 'preview0003' } }
}
"@

        function Invoke-Harness
        {
            param(
                [hashtable] $Extra = @{},

                # Imports the stale module last so it wins the function table,
                # exactly as the real installed build did.
                [switch] $LegacyShellPilot,

                # Ids the batch stub should return as failed results.
                [string[]] $FailIds = @()
            )

            # Re-assert the stubs immediately before each run, after removing any
            # ShellPilot a previous step may have pulled in. Temperature is
            # [object] so an unbound value stays $null rather than collapsing to
            # 0 - otherwise "omitted" and "-Temperature 0" look identical, and 0
            # is the value that matters most here.
            Remove-Module -Name ShellPilot -Force -ErrorAction SilentlyContinue
            Set-Item -LiteralPath 'function:global:Invoke-Shp' -Value $script:modernShpStub
            Set-Item -LiteralPath 'function:global:Clear-ShpChat' -Value $script:clearShpStub
            Set-Item -LiteralPath 'function:global:Invoke-ShpBatch' -Value $script:batchShpStub

            if ($LegacyShellPilot)
            {
                Import-Module -Name $script:staleManifest -Force -Global -ErrorAction Stop
            }

            $global:ShpStubCalls = [System.Collections.Generic.List[object]]::new()
            $global:ShpBatchCalls = [System.Collections.Generic.List[object]]::new()
            $global:ShpClearCalls = 0
            $global:ShpBatchFailIds = $FailIds
            Get-ChildItem -LiteralPath $script:workDir -File -ErrorAction SilentlyContinue | Remove-Item -Force

            # Sequential unless a test asks otherwise: the contexts below assert
            # on the per-call Invoke-Shp stub, so they have to measure the path
            # that makes those calls. Batch dispatch has its own context.
            $params = @{
                Mode        = 'Execute'
                QueryFile   = $script:queryFile
                TargetSkill = 'alpha-skill'
                SkillRoot   = $script:skillRoot
                WorkDir     = $script:workDir
                Repetitions = 1
                Dispatch    = 'Sequential'
            }
            foreach ($key in $Extra.Keys) { $params[$key] = $Extra[$key] }

            # *>$null keeps the harness's own progress and Write-Host output out
            # of the test log. It does not silence the one warning the
            # failure-isolation case provokes: Pester surfaces a warning raised
            # inside the batch ForEach-Object block into the build output even
            # through -WarningAction SilentlyContinue, -WarningAction Ignore and
            # a stream redirect, all three measured. That build warning names a
            # deliberately failed stub item and is expected.
            & $script:scriptPath @params *>$null
            $global:ShpStubCalls
        }
    }

    AfterAll {
        Remove-Module -Name ShellPilot -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath 'function:global:Invoke-Shp' -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath 'function:global:Invoke-ShpBatch' -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath 'function:global:Clear-ShpChat' -Force -ErrorAction SilentlyContinue
        Remove-Variable -Name ShpStubCalls -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable -Name ShpBatchCalls -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable -Name ShpClearCalls -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable -Name ShpBatchFailIds -Scope Global -ErrorAction SilentlyContinue
    }

    Context 'Parameter surface' {
        It 'Exposes a -Temperature parameter typed as a double' {
            $cmd = Get-Command -Name $script:scriptPath
            $cmd.Parameters.Keys | Should -Contain 'Temperature'
            $cmd.Parameters['Temperature'].ParameterType | Should -Be ([double])
        }

        It 'Validates -Temperature against the protocol range' {
            $attribute = (Get-Command -Name $script:scriptPath).Parameters['Temperature'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] }

            $attribute | Should -Not -BeNullOrEmpty
            $attribute.MinRange | Should -Be 0
            $attribute.MaxRange | Should -Be 2
        }

        It 'Rejects a temperature outside the range before any call is made' {
            { & $script:scriptPath -Mode Execute -QueryFile $script:queryFile -TargetSkill 'alpha-skill' `
                    -SkillRoot $script:skillRoot -WorkDir $script:workDir -Temperature 5 } |
                Should -Throw
        }

        # Get-Help does not surface this script's comment-based help at all -
        # pre-existing, unrelated to this parameter - so assert the documentation
        # from the source instead of through Get-Help.
        It 'Documents -Temperature in the comment-based help' {
            $raw = Get-Content -LiteralPath $script:scriptPath -Raw
            $raw | Should -Match '(?m)^\.PARAMETER Temperature\s*$'
        }
    }

    Context 'Forwarding' {
        It 'Forwards an explicit -Temperature to every judge call' {
            $calls = Invoke-Harness -Extra @{ Temperature = 0 }

            $calls.Count | Should -Be 4
            @($calls | Where-Object HadTemp).Count | Should -Be 4
            @($calls | Where-Object { $_.Temperature -ne 0 }) | Should -BeNullOrEmpty
        }

        # Omit-or-send, not defaulted: 0 is a meaningful temperature, so sending
        # a default would silently change the operating point of every existing
        # run rather than leaving it at the backend default.
        It 'Sends no temperature at all when the parameter is omitted' {
            $calls = Invoke-Harness

            $calls.Count | Should -Be 4
            @($calls | Where-Object HadTemp) | Should -BeNullOrEmpty
        }

        It 'Forwards a non-zero temperature unchanged' {
            $calls = Invoke-Harness -Extra @{ Temperature = 1.5 }

            @($calls | Where-Object { $_.Temperature -eq 1.5 }).Count | Should -Be 4
        }
    }

    Context 'Stale ShellPilot guard' {
        # Measured on 2026-08-11: the installed ShellPilot was 0.4.0-preview0003,
        # which predates -Temperature. Every one of 54 calls died in the parameter
        # binder with "A parameter cannot be found that matches parameter name
        # 'Temperature'", the run reported 54 failures, and nothing in that output
        # said the module was stale. The guard has to fire before the loop, and it
        # has to name the build it resolved.
        It 'Throws before any call when -Temperature meets a ShellPilot without it' {
            $thrown = { Invoke-Harness -LegacyShellPilot -Extra @{ Temperature = 0 } } |
                Should -Throw -PassThru

            $thrown.Exception.Message | Should -BeLike '*Invoke-Shp -Temperature*'
            $global:ShpStubCalls.Count | Should -Be 0
            @(Get-ChildItem -LiteralPath $script:workDir -File) |
                Should -BeNullOrEmpty -Because 'the guard must cost nothing, not even a prompt file'
        }

        It 'Names the resolved build and the fix in the failure' {
            $thrown = { Invoke-Harness -LegacyShellPilot -Extra @{ Temperature = 0 } } |
                Should -Throw -PassThru

            # The prerelease is the whole point: 0.4.0 alone reads as new enough.
            $thrown.Exception.Message | Should -BeLike '*0.4.0-preview0003*'
            $thrown.Exception.Message | Should -BeLike "*$script:staleModuleBase*"
            $thrown.Exception.Message | Should -BeLike '*Import-Module*'
        }

        # Only what the run needs is checked. An old ShellPilot answers every
        # other call in this harness perfectly well.
        It 'Runs against an older ShellPilot when -Temperature is omitted' {
            $calls = Invoke-Harness -LegacyShellPilot

            $calls.Count | Should -Be 4
            @($calls | Where-Object HadTemp) | Should -BeNullOrEmpty
        }
    }

    Context 'Batch dispatch parameter surface' {
        It 'Defaults -Dispatch to Batch and still offers Sequential' {
            $parameter = (Get-Command -Name $script:scriptPath).Parameters['Dispatch']
            $parameter | Should -Not -BeNullOrEmpty

            $set = $parameter.Attributes |
                Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $set.ValidValues | Should -Contain 'Batch'
            $set.ValidValues | Should -Contain 'Sequential'

            $raw = Get-Content -LiteralPath $script:scriptPath -Raw
            $raw | Should -Match "(?m)^\s*\[string\]\s*\`$Dispatch\s*=\s*'Batch'"
        }

        It 'Exposes a -ThrottleLimit that defaults to the conservative 4' {
            $raw = Get-Content -LiteralPath $script:scriptPath -Raw
            $raw | Should -Match "(?m)^\s*\[int\]\s*\`$ThrottleLimit\s*=\s*4"
        }

        It 'Documents both new parameters in the comment-based help' {
            $raw = Get-Content -LiteralPath $script:scriptPath -Raw
            $raw | Should -Match '(?m)^\.PARAMETER Dispatch\s*$'
            $raw | Should -Match '(?m)^\.PARAMETER ThrottleLimit\s*$'
        }
    }

    Context 'Batch dispatch' {
        It 'Sends the whole sweep in one batch instead of one call per prompt' {
            Invoke-Harness -Extra @{ Dispatch = 'Batch' } | Out-Null

            $global:ShpBatchCalls.Count | Should -Be 1
            $global:ShpBatchCalls[0].Ids.Count | Should -Be 4
            $global:ShpStubCalls | Should -BeNullOrEmpty -Because 'batch dispatch must not fall back to per-prompt calls'
        }

        # Every batch item is dispatched with -History @(), so there is no
        # session conversation to reset. Calling Clear-ShpChat anyway would be
        # harmless but would misdescribe the contract.
        It 'Never resets a session conversation the batch does not use' {
            Invoke-Harness -Extra @{ Dispatch = 'Batch' } | Out-Null

            $global:ShpClearCalls | Should -Be 0
        }

        It 'Still resets the conversation on the sequential path' {
            Invoke-Harness -Extra @{ Dispatch = 'Sequential' } | Out-Null

            $global:ShpClearCalls | Should -Be 4
        }

        It 'Forwards -ThrottleLimit and -Temperature to the batch' {
            Invoke-Harness -Extra @{ Dispatch = 'Batch'; ThrottleLimit = 7; Temperature = 0 } | Out-Null

            $global:ShpBatchCalls[0].ThrottleLimit | Should -Be 7
            $global:ShpBatchCalls[0].HadTemp | Should -BeTrue
            $global:ShpBatchCalls[0].Temperature | Should -Be 0
        }

        It 'Sends no temperature at all when the batch parameter is omitted' {
            Invoke-Harness -Extra @{ Dispatch = 'Batch' } | Out-Null

            $global:ShpBatchCalls[0].HadTemp | Should -BeFalse
        }

        # The stub returns results reversed on purpose. Correlating on position
        # would put every reply in the wrong file and still look successful, so
        # this asserts the content of each file, not just that files exist.
        It 'Writes each reply to the file named by its own id' {
            Invoke-Harness -Extra @{ Dispatch = 'Batch' } | Out-Null

            foreach ($id in 'pos-01', 'neg-01', 'pos-02', 'neg-02')
            {
                $path = Join-Path $script:workDir "$id.rep1.out.txt"
                Test-Path -LiteralPath $path | Should -BeTrue
                (Get-Content -LiteralPath $path -Raw) | Should -Match "answered:$id\.rep1"
            }
        }

        It 'Keeps every other reply when one item fails' {
            Invoke-Harness -Extra @{ Dispatch = 'Batch' } -FailIds 'neg-01.rep1' | Out-Null

            Test-Path -LiteralPath (Join-Path $script:workDir 'neg-01.rep1.out.txt') |
                Should -BeFalse -Because 'a failed item has no content to record'

            foreach ($id in 'pos-01', 'pos-02', 'neg-02')
            {
                Test-Path -LiteralPath (Join-Path $script:workDir "$id.rep1.out.txt") | Should -BeTrue
            }
        }

        It 'Names the batch command when a stale ShellPilot batch lacks -Temperature' {
            $thrown = { Invoke-Harness -LegacyShellPilot -Extra @{ Dispatch = 'Batch'; Temperature = 0 } } |
                Should -Throw -PassThru

            # The guard has to probe the command that will actually dispatch, so
            # the message names Invoke-ShpBatch even though Invoke-Shp is the
            # command the sequential path checks.
            $thrown.Exception.Message | Should -BeLike '*Invoke-ShpBatch -Temperature*'
            $thrown.Exception.Message | Should -BeLike '*0.4.0-preview0003*'
            $global:ShpStubCalls.Count | Should -Be 0
        }
    }
}
