Describe 'run-trigger-evals -Temperature' -Tag 'Unit' {
    BeforeAll {
        $script:scriptPath = Join-Path $PSScriptRoot (
            '../Skills/agent-evals/scripts/run-trigger-evals.ps1'
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
        function global:Invoke-Shp
        {
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

        # Execute mode also calls Clear-ShpChat between prompts. Leaving it
        # unstubbed makes PowerShell auto-load the INSTALLED ShellPilot to
        # resolve it, and that import then overwrites the Invoke-Shp stub above -
        # which is how this test first reached the live backend, and later failed
        # against an installed build too old to accept -Temperature. Every
        # ShellPilot command the harness touches has to be stubbed.
        function global:Clear-ShpChat { }

        function Invoke-Harness
        {
            param([hashtable] $Extra = @{})

            # Re-assert the stub immediately before each run, after removing any
            # real ShellPilot a previous step may have pulled in. Temperature is
            # [object] so an unbound value stays $null rather than collapsing to
            # 0 - otherwise "omitted" and "-Temperature 0" look identical, and 0
            # is the value that matters most here.
            Remove-Module -Name ShellPilot -Force -ErrorAction SilentlyContinue

            $global:ShpStubCalls = [System.Collections.Generic.List[object]]::new()
            Get-ChildItem -LiteralPath $script:workDir -File -ErrorAction SilentlyContinue | Remove-Item -Force

            $params = @{
                Mode        = 'Execute'
                QueryFile   = $script:queryFile
                TargetSkill = 'alpha-skill'
                SkillRoot   = $script:skillRoot
                WorkDir     = $script:workDir
                Repetitions = 1
            }
            & $script:scriptPath @params @Extra -WarningAction SilentlyContinue | Out-Null
            $global:ShpStubCalls
        }
    }

    AfterAll {
        Remove-Item -LiteralPath $script:tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath 'function:global:Invoke-Shp' -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath 'function:global:Clear-ShpChat' -Force -ErrorAction SilentlyContinue
        Remove-Variable -Name ShpStubCalls -Scope Global -ErrorAction SilentlyContinue
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
}
