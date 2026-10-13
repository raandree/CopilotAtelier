<#
    The Remote grant: how one explicit request in the user's prompt authorizes one
    remote mutation.

    Decision 0016, revision 2026-10-12. A hook ask cannot carry that
    authorization: the Copilot Agent Host approved it itself, in the same second,
    under the owner's Allow all level and chat.tools.global.autoApprove setting.
    So the guard stays a hard block, and a UserPromptSubmit hook records a
    Remote grant when the user's own prompt carries a Grant marker such as
    [[allow-remote: git push, gh pr create]]. The guard consumes the grant.

    Every case runs the real scripts in child processes, the way a host starts
    them, against a Grant root inside TestDrive.
#>

BeforeDiscovery {
    $script:isWindowsPlatform = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
    $script:windowsPowerShellAvailable = $script:isWindowsPlatform -and
        (Test-Path -LiteralPath (Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'))

    $script:markerCase = @(
        @{ Prompt = 'create it [[allow-remote: git push]]'; Expected = [ordered]@{ 'git push' = 1 } }
        @{ Prompt = '[[allow-remote: git push, gh pr create]]'; Expected = [ordered]@{ 'git push' = 1; 'gh pr create' = 1 } }
        @{ Prompt = '[[allow-remote: gh pr create x3]]'; Expected = [ordered]@{ 'gh pr create' = 3 } }
        @{ Prompt = '[[allow-remote: gh pr create x3, gh pr create x2]]'; Expected = [ordered]@{ 'gh pr create' = 5 } }
        @{ Prompt = '[[allow-remote: git push x99]]'; Expected = [ordered]@{ 'git push' = 20 } }
        @{ Prompt = '[[ ALLOW-REMOTE :  Git  Push , GH PR Create x2 ]]'; Expected = [ordered]@{ 'git push' = 1; 'gh pr create' = 2 } }
        @{ Prompt = '[[allow-remote: git push --force]]'; Expected = [ordered]@{ 'git push --force' = 1 } }
        @{ Prompt = '[[allow-remote: gh api]]'; Expected = [ordered]@{ 'gh api' = 1 } }
        @{ Prompt = '[[allow-remote: rm -rf, git push, git reset --hard]]'; Expected = [ordered]@{ 'git push' = 1 } }
        @{ Prompt = 'first [[allow-remote: git push]] and then [[allow-remote: gh issue comment]]'; Expected = [ordered]@{ 'git push' = 1; 'gh issue comment' = 1 } }
        @{ Prompt = "release it`n[[allow-remote: gh release create, gh workflow run]]`nthanks"; Expected = [ordered]@{ 'gh release create' = 1; 'gh workflow run' = 1 } }
    )

    $script:noMarkerCase = @(
        @{ Why = 'carries no marker'; Prompt = 'please create the PRs' }
        @{ Why = 'carries an empty marker'; Prompt = '[[allow-remote: ]]' }
        @{ Why = 'names an operation the guard does not know'; Prompt = '[[allow-remote: nonsense]]' }
        @{ Why = 'hides a zero-width space inside the phrase'; Prompt = ('[[allow-remote: git{0} push]]' -f [char]0x200B) }
        @{ Why = 'hides a soft hyphen inside the phrase'; Prompt = ('[[allow-remote: git{0} push]]' -f [char]0x00AD) }
        @{ Why = 'hides a word joiner inside the phrase'; Prompt = ('[[allow-remote: gh pr{0} create]]' -f [char]0x2060) }
        @{ Why = 'asks for a destructive local operation'; Prompt = '[[allow-remote: git reset --hard, git clean -fd, git commit --no-verify]]' }
        @{ Why = 'asks for zero uses'; Prompt = '[[allow-remote: git push x0]]' }
        @{ Why = 'uses single brackets'; Prompt = '[allow-remote: git push]' }
        @{ Why = 'leaves out the colon'; Prompt = '[[allow-remote git push]]' }
        @{ Why = 'spells the keyword differently'; Prompt = '[[allow remote: git push]]' }
        @{ Why = 'spreads the marker over two lines'; Prompt = "[[allow-remote: git push,`ngh pr create]]" }
        @{ Why = 'quotes the marker in an inline code span'; Prompt = 'what does `[[allow-remote: git push]]` do?' }
        @{ Why = 'quotes the marker in a double-backtick span'; Prompt = 'what does ``[[allow-remote: git push]]`` do?' }
        @{ Why = 'quotes the marker in a fenced code block'; Prompt = "see:`n``````text`n[[allow-remote: git push]]`n```````nthanks" }
        @{ Why = 'quotes the marker in a tilde-fenced code block'; Prompt = "see:`n~~~`n[[allow-remote: git push]]`n~~~`nthanks" }
        @{ Why = 'quotes the marker in a fenced block that never closes'; Prompt = "see:`n``````text`n[[allow-remote: git push]]" }
    )

    # Each of these must leave the guard blocking: the file is not a valid grant.
    $script:invalidGrantCase = @(
        @{ Why = 'is not JSON'; Content = 'not json' }
        @{ Why = 'is an array'; Content = '[]' }
        @{ Why = 'is empty'; Content = '' }
        @{ Why = 'has another schema version'; Patch = @{ schema = 2 } }
        @{ Why = 'names another session'; Patch = @{ sessionKey = 'someone-else' } }
        @{ Why = 'drops the session key'; Remove = 'sessionKey' }
        @{ Why = 'carries a negative count'; Patch = @{ operations = @{ 'git push' = -1 } } }
        @{ Why = 'carries a count above the cap'; Patch = @{ operations = @{ 'git push' = 21 } } }
        @{ Why = 'carries a fractional count'; Patch = @{ operations = @{ 'git push' = 1.5 } } }
        @{ Why = 'carries a count as text'; Patch = @{ operations = @{ 'git push' = '1' } } }
        @{ Why = 'names an operation the guard does not know'; Patch = @{ operations = @{ 'git push' = 1; 'git reset --hard' = 1 } } }
        @{ Why = 'names no operation'; Patch = @{ operations = @{} } }
        @{ Why = 'carries operations of the wrong type'; Patch = @{ operations = 'git push' } }
        @{ Why = 'has text for a time'; Patch = @{ expiresAt = 'tomorrow' } }
        @{ Why = 'has expired'; Patch = @{ issuedAt = -100; expiresAt = -10 } }
        @{ Why = 'was issued in the future'; Patch = @{ issuedAt = 3600; expiresAt = 4200 } }
        @{ Why = 'outlives one hour'; Patch = @{ issuedAt = -10; expiresAt = 7200 } }
        @{ Why = 'ends before it begins'; Patch = @{ issuedAt = -10; expiresAt = -20 } }
    )

    $script:forceCase = @(
        @{ Command = 'git push --force origin main' }
        @{ Command = 'git push -f origin main' }
        @{ Command = 'git push --force-with-lease origin main' }
        @{ Command = 'git push --force-with-lease=main:abc123 origin main' }
        @{ Command = 'git push --force-if-includes origin main' }
        @{ Command = 'git push -uf origin main' }
        @{ Command = 'git push --delete origin old-branch' }
        @{ Command = 'git push -d origin old-branch' }
        @{ Command = 'git push --mirror origin' }
        @{ Command = 'git push --prune origin' }
        @{ Command = 'git push --all origin' }
        @{ Command = 'git push --tags' }
        @{ Command = 'git push --tags origin' }
        @{ Command = 'git push origin +main' }
        @{ Command = 'git push origin +main:main' }
        @{ Command = 'git push origin :old-branch' }
        @{ Command = 'git push origin +:old-branch' }
    )

    $script:plainPushCase = @(
        @{ Command = 'git push' }
        @{ Command = 'git push origin main' }
        @{ Command = 'git push -u origin ai/feature' }
        @{ Command = 'git push --set-upstream origin ai/feature' }
        @{ Command = 'git push --follow-tags origin main' }
        @{ Command = 'git push --dry-run origin main' }
        @{ Command = 'git push origin HEAD:refs/heads/ai/feature' }
        @{ Command = 'git -C D:\repo push origin main' }
        @{ Command = 'git.exe push origin main' }

        # Forms that run the push once, where it is written. A control for the rules that ask for 20 uses.
        @{ Command = 'try { git push origin main } catch { Write-Error $_ }' }
        @{ Command = 'if ($true) { git push origin main } else { git status }' }
        @{ Command = 'git push origin main 2>&1 | Out-String' }
        @{ Command = '$r = git push origin main' }
        @{ Command = 'git push origin main && git status' }
        @{ Command = 'Set-Location D:\repo; git push origin main' }
        @{ Command = '$ErrorActionPreference = ''Stop''; git push origin main' }
        @{ Command = 'Push-Location D:\repo; try { git push origin main } finally { Pop-Location }' }
        @{ Command = '$h = @{ a = 1 }; git push origin main | Out-Null; $LASTEXITCODE' }
        @{ Command = '& git push origin main' }
        @{ Command = "Invoke-Expression 'git push origin main'" }
        @{ Command = 'cmd /c "git push origin main"' }
        @{ Command = 'bash -c "cd repo && git push origin main"' }
        @{ Command = 'powershell -NoProfile -Command "git push origin main"' }
        @{ Command = 'git push origin main )' }
        @{ Command = 'git status && git push origin main' }

        # Review of 2026-10-13, fourth pass, I3: a cmdlet whose name only starts with Register- schedules nothing.
        @{ Command = 'git push origin main; Register-PSRepository -Default' }
        @{ Command = 'Register-PSRepository -Default; git push origin main' }
        @{ Command = 'git push origin main; Register-PackageSource -Name x -ProviderName y -Location z' }
    )

    # Commands that can run a blocked operation more than once. The guard counts what it reads, not
    # what runs, so each of them asks for every use the marker can grant (review of 2026-10-13, F3).
    $script:repetitionCase = @(
        @{ Reason = 'a ForEach-Object over branches'; Command = 'git branch --format=%(refname:short) | ForEach-Object { git push origin $_ }'; Phrase = 'git push' }
        @{ Reason = 'a foreach statement'; Command = "foreach (`$b in 'a', 'b') { git push origin `$b }"; Phrase = 'git push' }
        @{ Reason = 'the % alias'; Command = '1..3 | % { git push origin main }'; Phrase = 'git push' }
        @{ Reason = 'a function called twice'; Command = 'function Publish { git push }; Publish; Publish'; Phrase = 'git push' }
        @{ Reason = 'a for statement'; Command = 'for ($i = 0; $i -lt 3; $i++) { git push }'; Phrase = 'git push' }
        @{ Reason = 'a while statement'; Command = 'while ($true) { git push }'; Phrase = 'git push' }
        @{ Reason = 'a shell for loop'; Command = 'for b in a b; do git push origin $b; done'; Phrase = 'git push' }
        @{ Reason = 'xargs'; Command = 'git branch | xargs -n1 git push origin'; Phrase = 'git push' }
        @{ Reason = 'a script block called through the call operator'; Command = '$run = { git push }; & $run; & $run'; Phrase = 'git push' }
        @{ Reason = 'a loop over pull requests'; Command = "foreach (`$b in 'a', 'b') { gh pr create --head `$b --fill }"; Phrase = 'gh pr create' }
        @{ Reason = 'the ForEach method'; Command = '(1..5).ForEach({ git push origin main })'; Phrase = 'git push' }
        @{ Reason = 'the Where method followed by ForEach'; Command = '(1..5).Where({ $true }).ForEach({ git push origin main })'; Phrase = 'git push' }
        @{ Reason = 'the foreach alias'; Command = '1..5 | foreach { git push origin main }'; Phrase = 'git push' }
        @{ Reason = 'the ? alias'; Command = '1..5 | ? { git push origin main }'; Phrase = 'git push' }
        @{ Reason = 'a cmd for /l loop'; Command = 'cmd /c "for /l %i in (1,1,5) do git push origin main"'; Phrase = 'git push' }
        @{ Reason = 'a script block invoked more than once'; Command = '$sb = { git push origin main }; $sb.Invoke(); $sb.Invoke()'; Phrase = 'git push' }
        @{ Reason = 'a switch statement over several values'; Command = 'switch (1..3) { default { git push origin main } }'; Phrase = 'git push' }
        @{ Reason = 'a switch statement with options'; Command = 'switch -Regex (''a'', ''b'') { ''.'' { git push origin main } }'; Phrase = 'git push' }
        @{ Reason = 'a loop in a pull request command with prose in its title'; Command = "foreach (`$b in 'a', 'b') { gh pr create --head `$b --title `"function x`" --fill }"; Phrase = 'gh pr create' }

        # Review of 2026-10-13, third pass, H5, and the class behind it: code that is written once and can run any
        # number of times, however the syntax around it looks. The guard counts what it reads, not what runs.
        @{ Reason = 'a script block as the sort key'; Command = '1..3 | Sort-Object { git push origin main }'; Phrase = 'git push' }
        @{ Reason = 'a script block as the grouping key'; Command = '1..3 | Group-Object { git push origin main }'; Phrase = 'git push' }
        @{ Reason = 'a script block in a calculated property'; Command = "1..3 | Select-Object @{ n = 'a'; e = { git push origin main } }"; Phrase = 'git push' }
        @{ Reason = 'an event handler on a timer'; Command = '$t = New-Object Timers.Timer 1000; Register-ObjectEvent $t Elapsed -Action { git push origin main }; $t.Start()'; Phrase = 'git push' }
        @{ Reason = 'a script block that is dot-sourced three times'; Command = '$x = { git push origin main }; . $x; . $x; . $x'; Phrase = 'git push' }
        @{ Reason = 'a script block run in place with the call operator'; Command = '& { git push origin main }'; Phrase = 'git push' }
        @{ Reason = 'a script block run on several computers'; Command = 'Invoke-Command -ComputerName a, b, c -ScriptBlock { git push origin main }'; Phrase = 'git push' }
        @{ Reason = 'a script block held in a variable and given to Invoke-Command'; Command = '$run = { gh pr create --fill }; Invoke-Command $run'; Phrase = 'gh pr create' }
        @{ Reason = 'a variable that Invoke-Expression runs three times'; Command = "`$c = 'git push origin main'; iex `$c; iex `$c; iex `$c"; Phrase = 'git push' }
        @{ Reason = 'a variable that Invoke-Expression runs twice, spelled out'; Command = "`$c = 'git push origin main'; Invoke-Expression `$c; Invoke-Expression `$c"; Phrase = 'git push' }
        @{ Reason = 'a variable that a nested shell runs twice'; Command = "`$c = 'git push origin main'; cmd /c `$c; cmd /c `$c"; Phrase = 'git push' }
        @{ Reason = 'a variable piped into Invoke-Expression'; Command = "`$c = 'git push origin main'; `$c | Invoke-Expression; `$c | Invoke-Expression"; Phrase = 'git push' }
        @{ Reason = 'a script block built from a string'; Command = "`$b = [scriptblock]::Create('git push origin main'); `$b.Invoke(); `$b.Invoke()"; Phrase = 'git push' }
        @{ Reason = 'a class method that is called three times'; Command = 'class P { [void] Go() { git push origin main } }; $p = [P]::new(); $p.Go(); $p.Go(); $p.Go()'; Phrase = 'git push' }
        @{ Reason = 'a script method that is called three times'; Command = '$o = New-Object psobject; Add-Member -InputObject $o -MemberType ScriptMethod -Name Go -Value { git push origin main }; $o.Go(); $o.Go(); $o.Go()'; Phrase = 'git push' }
        @{ Reason = 'a trap that runs on every error'; Command = 'trap { git push origin main; continue }; 1 / 0; 1 / 0'; Phrase = 'git push' }
        @{ Reason = 'a scheduled task'; Command = 'schtasks /create /tn x /tr "git push origin main" /sc minute'; Phrase = 'git push' }
        @{ Reason = 'a crontab entry'; Command = 'echo "* * * * * git push origin main" | crontab -'; Phrase = 'git push' }
        @{ Reason = 'a shell while loop'; Command = 'sh -c ''while true; do git push origin main; done'''; Phrase = 'git push' }
        @{ Reason = 'a shell until loop that retries'; Command = 'until git push origin main; do sleep 5; done'; Phrase = 'git push' }
        @{ Reason = 'a shell while loop that retries after a failure'; Command = 'while ! git push origin main; do sleep 5; done'; Phrase = 'git push' }
        @{ Reason = 'a bash arithmetic for loop'; Command = 'bash -c ''for ((i=0; i<3; i++)); do git push origin main; done'''; Phrase = 'git push' }
        @{ Reason = 'watch'; Command = 'watch -n 60 git push origin main'; Phrase = 'git push' }
        @{ Reason = 'a retry wrapper'; Command = 'retry 3 git push origin main'; Phrase = 'git push' }
        @{ Reason = 'inline Python code, which may loop'; Command = 'python -c "import os; os.system(''git push origin main'')"'; Phrase = 'git push' }
        @{ Reason = 'inline Node code, which may loop'; Command = 'node -e "require(''child_process'').execSync(''git push origin main'')"'; Phrase = 'git push' }

        # Review of 2026-10-13, fourth pass, I2 and I4: repeat shapes that asked for one use, and a separator that
        # was mistaken for a refspec.
        @{ Reason = 'a cmd for loop with no semicolon before do'; Command = 'for %i in (1 2 3) do git push origin main'; Phrase = 'git push' }
        @{ Reason = 'a batch file for loop with doubled percent signs'; Command = 'for %%i in (1 2 3) do git push origin main'; Phrase = 'git push' }
        @{ Reason = 'a cmd for loop run through cmd /c'; Command = 'cmd /c "for %i in (1 2 3) do git push origin main"'; Phrase = 'git push' }
        @{ Reason = 'watchexec, which runs the command on every change'; Command = 'watchexec -- git push origin main'; Phrase = 'git push' }
        @{ Reason = 'nodemon, which restarts the command on every change'; Command = 'nodemon --exec "git push origin main"'; Phrase = 'git push' }
        @{ Reason = 'entr, which runs the command on every change'; Command = 'ls *.md | entr git push origin main'; Phrase = 'git push' }
        @{ Reason = 'GNU parallel, whose ::: separator is not a refspec'; Command = 'parallel git push origin ::: a b c'; Phrase = 'git push' }
        @{ Reason = 'a registered scheduled task after the push'; Command = 'git push origin main; Register-ScheduledTask -TaskName x -Action $a -Trigger $t'; Phrase = 'git push' }
        @{ Reason = 'a registered event, which has no script block'; Command = 'Register-ObjectEvent -InputObject $t -EventName Elapsed -SourceIdentifier x; git push origin main'; Phrase = 'git push' }
        @{ Reason = 'a script block in a text that does not parse, so no syntax tree can tell what it is'; Command = '1..3 | Sort-Object { git push origin main } )'; Phrase = 'git push' }
        @{ Reason = 'a function defined through the Function drive and called twice'; Command = 'Set-Item function:deploy ''git push origin main''; deploy; deploy'; Phrase = 'git push' }
        @{ Reason = 'a function assigned through the Function drive and called twice'; Command = '$function:deploy = ''git push origin main''; deploy; deploy'; Phrase = 'git push' }
        @{ Reason = 'a function created with New-Item on the Function drive and called twice'; Command = 'New-Item -Path function: -Name deploy -Value ''git push origin main''; deploy; deploy'; Phrase = 'git push' }
        @{ Reason = 'compiled code that is called twice'; Command = 'Add-Type -TypeDefinition ''public class X { public static void Go() { System.Diagnostics.Process.Start("cmd", "/c git push origin main"); } }''; [X]::Go(); [X]::Go()'; Phrase = 'git push' }
        @{ Reason = 'a script block after && in Windows PowerShell, which cannot parse it'; Command = 'git status && 1..3 | Sort-Object { git push origin main }'; Phrase = 'git push' }
        @{ Reason = 'a repeat wrapper after a pipeline'; Command = 'cd repo && repeat 3 git push origin main'; Phrase = 'git push' }
    )

    $script:ghCase = @(
        @{ Command = 'gh pr create --fill'; Phrase = 'gh pr create' }
        @{ Command = 'gh pr merge 42 --squash'; Phrase = 'gh pr merge' }
        @{ Command = 'gh -R o/r pr create --fill'; Phrase = 'gh pr create' }
        @{ Command = 'gh --repo=o/r issue comment 42 --body hi'; Phrase = 'gh issue comment' }
        @{ Command = 'gh release create v1.0.0 --notes x'; Phrase = 'gh release create' }
        @{ Command = 'gh repo delete o/r --yes'; Phrase = 'gh repo delete' }
        @{ Command = 'gh workflow run ci.yml'; Phrase = 'gh workflow run' }
        @{ Command = 'gh secret set TOKEN --body abc'; Phrase = 'gh secret set' }
        @{ Command = 'gh cache delete --all'; Phrase = 'gh cache delete' }
        @{ Command = 'gh api -X POST repos/o/r/issues'; Phrase = 'gh api' }
        @{ Command = 'gh api --method DELETE repos/o/r'; Phrase = 'gh api' }
        @{ Command = 'gh api graphql -f query=''mutation { x }'''; Phrase = 'gh api' }
        @{ Command = 'GH.EXE PR CREATE --fill'; Phrase = 'gh pr create' }
    )

    $script:destructiveCase = @(
        @{ Command = 'git reset --hard HEAD~1'; Operation = 'discards work with a hard reset' }
        @{ Command = 'git clean -fdx'; Operation = 'force-deletes untracked files' }
        @{ Command = 'git commit -m "x" --no-verify'; Operation = 'bypasses repository hooks' }
        @{ Command = 'git push origin main --no-verify'; Operation = 'bypasses repository hooks' }
    )
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:scriptRoot = Join-Path -Path $script:repoRoot -ChildPath 'com.github.copilot/hooks/scripts'
    $script:guardScript = Join-Path -Path $script:scriptRoot -ChildPath 'Block-RemoteMutation.ps1'
    $script:grantScript = Join-Path -Path $script:scriptRoot -ChildPath 'Add-RemoteGrant.ps1'
    $script:hookConfigPath = Join-Path -Path $script:repoRoot -ChildPath 'com.github.copilot/hooks/hooks.json'
    $script:powerShellPath = (Get-Process -Id $PID).Path
    $script:windowsPowerShellPath = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
    }

    function script:Start-HookProcess {
        param(
            [Parameter(Mandatory)]
            [string]$ScriptPath,

            [Parameter(Mandatory)]
            [AllowEmptyString()]
            [string]$Payload,

            [Parameter()]
            [string[]]$ArgumentList = @(),

            [Parameter()]
            [string]$PowerShellPath = $script:powerShellPath,

            [Parameter()]
            [hashtable]$Environment = @{}
        )

        $utf8 = [Text.UTF8Encoding]::new($false)
        $startInfo = [Diagnostics.ProcessStartInfo]::new($PowerShellPath)
        $startInfo.Arguments = (@('-NoProfile', '-NonInteractive', '-File', ('"{0}"' -f $ScriptPath)) + $ArgumentList) -join ' '
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.StandardOutputEncoding = $utf8
        $startInfo.StandardErrorEncoding = $utf8
        $startInfo.EnvironmentVariables.Remove('COPILOT_ATELIER_ALLOW_REMOTE')
        foreach ($name in $Environment.Keys) {
            $startInfo.EnvironmentVariables[$name] = [string]$Environment[$name]
        }

        $process = [Diagnostics.Process]::Start($startInfo)
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        $bytes = $utf8.GetBytes($Payload)
        $process.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
        $process.StandardInput.Close()

        [pscustomobject]@{ Process = $process; OutputTask = $outputTask; ErrorTask = $errorTask }
    }

    function script:Wait-HookProcess {
        param(
            [Parameter(Mandatory)]
            [object]$Started
        )

        try {
            if (-not $Started.Process.WaitForExit(60000)) {
                $Started.Process.Kill()
                throw 'A hook script did not exit within 60 seconds.'
            }

            $Started.Process.WaitForExit()
            [pscustomobject]@{
                ExitCode = $Started.Process.ExitCode
                StdOut = $Started.OutputTask.Result
                StdErr = $Started.ErrorTask.Result
                Output = "$($Started.OutputTask.Result)$($Started.ErrorTask.Result)"
            }
        } finally {
            $Started.Process.Dispose()
        }
    }

    function script:Invoke-Guard {
        param(
            [Parameter(Mandatory)]
            [AllowEmptyString()]
            [string]$Payload,

            [Parameter()]
            [string]$GrantRoot,

            [Parameter()]
            [string]$PowerShellPath = $script:powerShellPath,

            [Parameter()]
            [hashtable]$Environment = @{}
        )

        $argumentList = @()
        if ($GrantRoot) {
            $argumentList = @('-GrantRoot', ('"{0}"' -f $GrantRoot))
        }

        $started = script:Start-HookProcess -ScriptPath $script:guardScript -Payload $Payload -ArgumentList $argumentList -PowerShellPath $PowerShellPath -Environment $Environment
        script:Wait-HookProcess -Started $started
    }

    function script:Invoke-Grant {
        param(
            [Parameter(Mandatory)]
            [AllowEmptyString()]
            [string]$Payload,

            [Parameter(Mandatory)]
            [string]$GrantRoot,

            [Parameter()]
            [string[]]$ExtraArgument = @(),

            [Parameter()]
            [string]$PowerShellPath = $script:powerShellPath
        )

        $argumentList = @('-GrantRoot', ('"{0}"' -f $GrantRoot)) + $ExtraArgument
        $started = script:Start-HookProcess -ScriptPath $script:grantScript -Payload $Payload -ArgumentList $argumentList -PowerShellPath $PowerShellPath
        script:Wait-HookProcess -Started $started
    }

    function script:New-ToolPayload {
        param(
            [Parameter(Mandatory)]
            [string]$Command,

            [Parameter()]
            [AllowNull()]
            [string]$SessionId = 'sess-1'
        )

        $payload = [ordered]@{ hook_event_name = 'PreToolUse' }
        if ($null -ne $SessionId) {
            $payload.session_id = $SessionId
        }

        $payload.tool_name = 'run_in_terminal'
        $payload.tool_input = [ordered]@{ command = $Command }
        $payload | ConvertTo-Json -Depth 5 -Compress
    }

    function script:New-PromptPayload {
        param(
            [Parameter(Mandatory)]
            [AllowEmptyString()]
            [string]$Prompt,

            [Parameter()]
            [AllowNull()]
            [string]$SessionId = 'sess-1'
        )

        $payload = [ordered]@{ hook_event_name = 'UserPromptSubmit' }
        if ($null -ne $SessionId) {
            $payload.session_id = $SessionId
        }

        $payload.prompt = $Prompt
        $payload | ConvertTo-Json -Depth 5 -Compress
    }

    function script:Get-UnixSecond {
        [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    }

    # The rule both scripts follow: a session id that is already a safe file name, lower case so that two
    # ids never differ only in case on a case-insensitive file system, stays as it is, and any other id
    # becomes h- and the SHA-256 of the id, so two ids never share one grant file.
    function script:Get-ExpectedGrantKey {
        param(
            [Parameter(Mandatory)]
            [AllowEmptyString()]
            [string]$SessionId
        )

        $usable = $SessionId -creplace '[^A-Za-z0-9._-]', ''
        if ([string]::IsNullOrEmpty($usable)) {
            return ''
        }

        if ($SessionId -cmatch '\A[a-z0-9_-]{1,64}\z') {
            return $SessionId
        }

        'h-' + (script:Get-Sha256 -Text $SessionId)
    }

    # The schema a hand-written grant has to follow; the guard validates it.
    function script:New-GrantFile {
        param(
            [Parameter(Mandatory)]
            [string]$Root,

            [Parameter()]
            [string]$SessionId = 'sess-1',

            [Parameter()]
            [System.Collections.IDictionary]$Operation = ([ordered]@{ 'git push' = 1 }),

            [Parameter()]
            [int]$IssuedOffsetSecond = -5,

            [Parameter()]
            [int]$LifetimeSecond = 600
        )

        $null = New-Item -ItemType Directory -Path $Root -Force
        $key = script:Get-ExpectedGrantKey -SessionId $SessionId
        $issued = (script:Get-UnixSecond) + $IssuedOffsetSecond
        $grant = [ordered]@{
            schema = 1
            sessionKey = $key
            issuedAt = $issued
            expiresAt = $issued + $LifetimeSecond
            operations = $Operation
        }

        $path = Join-Path -Path $Root -ChildPath "grant-$key.json"
        [IO.File]::WriteAllText($path, ($grant | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
        $path
    }

    function script:Read-Grant {
        param(
            [Parameter(Mandatory)]
            [string]$Path
        )

        [IO.File]::ReadAllText($Path) | ConvertFrom-Json
    }

    function script:Get-Sha256 {
        param(
            [Parameter(Mandatory)]
            [AllowEmptyString()]
            [string]$Text
        )

        $sha = [Security.Cryptography.SHA256]::Create()
        try {
            [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-', '').ToLowerInvariant()
        } finally {
            $sha.Dispose()
        }
    }
}

Describe 'Add-RemoteGrant' -Tag 'Unit' {
    BeforeEach {
        $script:root = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
    }

    It 'records a Remote grant for the session when the prompt carries a Grant marker' {
        $prompt = 'please create the PRs [[allow-remote: git push, gh pr create]]'
        $before = script:Get-UnixSecond

        $result = script:Invoke-Grant -Payload (script:New-PromptPayload -Prompt $prompt) -GrantRoot $script:root

        $result.ExitCode | Should -Be 0 -Because $result.Output
        $path = Join-Path -Path $script:root -ChildPath 'grant-sess-1.json'
        Test-Path -LiteralPath $path -PathType Leaf | Should -Be $true -Because $result.Output
        $grant = script:Read-Grant -Path $path
        $grant.schema | Should -Be 1
        $grant.sessionKey | Should -BeExactly 'sess-1'
        $grant.issuedAt | Should -BeGreaterOrEqual $before
        $grant.issuedAt | Should -BeLessOrEqual ((script:Get-UnixSecond) + 1)
        ($grant.expiresAt - $grant.issuedAt) | Should -Be 900 -Because 'a Remote grant lasts 15 minutes'
        $grant.promptSha256 | Should -BeExactly (script:Get-Sha256 -Text $prompt)
        @($grant.operations.PSObject.Properties.Name) | Should -Be @('git push', 'gh pr create')
    }

    It 'prints nothing on standard output, so a host reads no decision from it' {
        $result = script:Invoke-Grant -Payload (script:New-PromptPayload -Prompt '[[allow-remote: git push]]') -GrantRoot $script:root

        $result.ExitCode | Should -Be 0 -Because $result.Output
        $result.StdOut | Should -BeNullOrEmpty
    }

    It 'reads <Prompt> as <Expected>' -ForEach $script:markerCase {
        $result = script:Invoke-Grant -Payload (script:New-PromptPayload -Prompt $Prompt) -GrantRoot $script:root

        $result.ExitCode | Should -Be 0 -Because $result.Output
        $grant = script:Read-Grant -Path (Join-Path -Path $script:root -ChildPath 'grant-sess-1.json')
        $actual = [ordered]@{}
        foreach ($property in $grant.operations.PSObject.Properties) {
            $actual[$property.Name] = $property.Value
        }

        ($actual.Keys | Sort-Object) | Should -Be ($Expected.Keys | Sort-Object)
        foreach ($name in $Expected.Keys) {
            $actual[$name] | Should -Be $Expected[$name] -Because $name
        }
    }

    It 'records no grant when the prompt <Why>' -ForEach $script:noMarkerCase {
        $result = script:Invoke-Grant -Payload (script:New-PromptPayload -Prompt $Prompt) -GrantRoot $script:root

        $result.ExitCode | Should -Be 0 -Because $result.Output
        @(Get-ChildItem -LiteralPath $script:root -Filter 'grant-*.json' -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It 'replaces the grant of the previous prompt instead of adding to it' {
        $null = script:Invoke-Grant -Payload (script:New-PromptPayload -Prompt '[[allow-remote: git push x3]]') -GrantRoot $script:root
        $null = script:Invoke-Grant -Payload (script:New-PromptPayload -Prompt '[[allow-remote: gh pr create]]') -GrantRoot $script:root

        $grant = script:Read-Grant -Path (Join-Path -Path $script:root -ChildPath 'grant-sess-1.json')
        @($grant.operations.PSObject.Properties.Name) | Should -Be @('gh pr create')
    }

    It 'ends the grant of the previous prompt when the next prompt carries no marker' {
        $null = script:Invoke-Grant -Payload (script:New-PromptPayload -Prompt '[[allow-remote: git push]]') -GrantRoot $script:root
        $path = Join-Path -Path $script:root -ChildPath 'grant-sess-1.json'
        Test-Path -LiteralPath $path | Should -Be $true

        $result = script:Invoke-Grant -Payload (script:New-PromptPayload -Prompt 'thanks, now summarize') -GrantRoot $script:root

        $result.ExitCode | Should -Be 0 -Because $result.Output
        Test-Path -LiteralPath $path | Should -Be $false
    }

    It 'leaves the grant of another session alone' {
        $null = script:Invoke-Grant -Payload (script:New-PromptPayload -Prompt '[[allow-remote: git push]]' -SessionId 'sess-other') -GrantRoot $script:root

        $null = script:Invoke-Grant -Payload (script:New-PromptPayload -Prompt 'no marker here' -SessionId 'sess-1') -GrantRoot $script:root

        Test-Path -LiteralPath (Join-Path -Path $script:root -ChildPath 'grant-sess-other.json') | Should -Be $true
    }

    It 'records no grant when the payload names no session' {
        $result = script:Invoke-Grant -Payload (script:New-PromptPayload -Prompt '[[allow-remote: git push]]' -SessionId $null) -GrantRoot $script:root

        $result.ExitCode | Should -Be 0 -Because $result.Output
        @(Get-ChildItem -LiteralPath $script:root -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It 'records no grant when the session id holds no usable character' {
        $result = script:Invoke-Grant -Payload (script:New-PromptPayload -Prompt '[[allow-remote: git push]]' -SessionId '///') -GrantRoot $script:root

        $result.ExitCode | Should -Be 0 -Because $result.Output
        @(Get-ChildItem -LiteralPath $script:root -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It 'never fails: <Why>' -ForEach @(
        @{ Why = 'the payload is not JSON'; Payload = 'not json at all' }
        @{ Why = 'the payload is empty'; Payload = '' }
        @{ Why = 'the payload has no prompt'; Payload = '{"hook_event_name":"UserPromptSubmit","session_id":"sess-1"}' }
        @{ Why = 'the prompt is a number'; Payload = '{"session_id":"sess-1","prompt":42}' }
        @{ Why = 'the prompt is an array'; Payload = '{"session_id":"sess-1","prompt":["[[allow-remote: git push]]"]}' }
        @{ Why = 'the prompt is null'; Payload = '{"session_id":"sess-1","prompt":null}' }
    ) {
        $result = script:Invoke-Grant -Payload $Payload -GrantRoot $script:root

        $result.ExitCode | Should -Be 0 -Because 'a non-zero exit would block or warn on every prompt'
        $result.StdOut | Should -BeNullOrEmpty
        @(Get-ChildItem -LiteralPath $script:root -Filter 'grant-*.json' -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It 'keeps the file inside the Grant root for the session id <SessionId>' -ForEach @(
        @{ SessionId = '../../escape' }
        @{ SessionId = 'a/b\c:d' }
        @{ SessionId = 'weird id with spaces' }
        @{ SessionId = ('x' * 80) }
        @{ SessionId = 'dotted.id' }
    ) {
        $parent = Split-Path -Parent $script:root
        $before = @(Get-ChildItem -LiteralPath $parent -Recurse -File -ErrorAction SilentlyContinue).Count
        $key = script:Get-ExpectedGrantKey -SessionId $SessionId

        $result = script:Invoke-Grant -Payload (script:New-PromptPayload -Prompt '[[allow-remote: git push]]' -SessionId $SessionId) -GrantRoot $script:root

        $result.ExitCode | Should -Be 0 -Because $result.Output
        $key | Should -Match '\Ah-[0-9a-f]{64}\z' -Because 'an id that is not already a safe file name is hashed'
        (Test-Path -LiteralPath (Join-Path -Path $script:root -ChildPath "grant-$key.json")) | Should -Be $true
        @(Get-ChildItem -LiteralPath $script:root -File).Count | Should -Be 1
        @(Get-ChildItem -LiteralPath $parent -Recurse -File -ErrorAction SilentlyContinue).Count | Should -Be ($before + 1)
    }

    It 'keeps a session id that is already a lower-case safe file name as it is' {
        $sessionId = '8b2534f0-ce51-43b9-aa16-c7c20431219d'

        $result = script:Invoke-Grant -Payload (script:New-PromptPayload -Prompt '[[allow-remote: git push]]' -SessionId $sessionId) -GrantRoot $script:root

        $result.ExitCode | Should -Be 0 -Because $result.Output
        (Test-Path -LiteralPath (Join-Path -Path $script:root -ChildPath "grant-$sessionId.json")) | Should -Be $true
    }

    It 'hashes a session id with an upper-case letter, so a twin that differs only in case has its own file' {
        $upper = '8B2534F0-CE51-43B9-AA16-C7C20431219D'
        $lower = $upper.ToLowerInvariant()

        $null = script:Invoke-Grant -Payload (script:New-PromptPayload -Prompt '[[allow-remote: git push]]' -SessionId $lower) -GrantRoot $script:root
        $null = script:Invoke-Grant -Payload (script:New-PromptPayload -Prompt 'no marker in this one' -SessionId $upper) -GrantRoot $script:root

        # The prompt of the twin must not have ended the grant of the lower-case session.
        (Test-Path -LiteralPath (Join-Path -Path $script:root -ChildPath "grant-$lower.json")) | Should -Be $true
        (script:Get-ExpectedGrantKey -SessionId $upper) | Should -Match '\Ah-[0-9a-f]{64}\z'
    }

    It 'removes grant files older than a day and leaves every other file alone' {
        $null = New-Item -ItemType Directory -Path $script:root -Force
        $old = Join-Path -Path $script:root -ChildPath 'grant-stale.json'
        $recent = Join-Path -Path $script:root -ChildPath 'grant-recent.json'
        $other = Join-Path -Path $script:root -ChildPath 'notes.txt'
        foreach ($path in $old, $recent, $other) {
            [IO.File]::WriteAllText($path, '{}')
        }

        (Get-Item -LiteralPath $old).LastWriteTimeUtc = [DateTime]::UtcNow.AddDays(-2)
        (Get-Item -LiteralPath $other).LastWriteTimeUtc = [DateTime]::UtcNow.AddDays(-2)

        $result = script:Invoke-Grant -Payload (script:New-PromptPayload -Prompt 'hello') -GrantRoot $script:root

        $result.ExitCode | Should -Be 0 -Because $result.Output
        Test-Path -LiteralPath $old | Should -Be $false
        Test-Path -LiteralPath $recent | Should -Be $true
        Test-Path -LiteralPath $other | Should -Be $true
    }

    It 'lets a test shorten the lifetime' {
        $null = script:Invoke-Grant -Payload (script:New-PromptPayload -Prompt '[[allow-remote: git push]]') -GrantRoot $script:root -ExtraArgument @('-LifetimeMinute', '5')

        $grant = script:Read-Grant -Path (Join-Path -Path $script:root -ChildPath 'grant-sess-1.json')
        ($grant.expiresAt - $grant.issuedAt) | Should -Be 300
    }

    It 'writes a grant under Windows PowerShell as well' -Skip:(-not $script:windowsPowerShellAvailable) {
        $result = script:Invoke-Grant -Payload (script:New-PromptPayload -Prompt '[[allow-remote: git push x2]]') -GrantRoot $script:root -PowerShellPath $script:windowsPowerShellPath

        $result.ExitCode | Should -Be 0 -Because $result.Output
        $grant = script:Read-Grant -Path (Join-Path -Path $script:root -ChildPath 'grant-sess-1.json')
        $grant.operations.'git push' | Should -Be 2
    }
}

Describe 'Block-RemoteMutation with a Remote grant' -Tag 'Unit' {
    BeforeEach {
        $script:root = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
    }

    It 'allows a push once under a matching grant and blocks the next one' {
        $path = script:New-GrantFile -Root $script:root
        $payload = script:New-ToolPayload -Command 'git push origin main'

        $first = script:Invoke-Guard -Payload $payload -GrantRoot $script:root
        $second = script:Invoke-Guard -Payload $payload -GrantRoot $script:root

        $first.ExitCode | Should -Be 0 -Because $first.Output
        $first.StdOut | Should -BeNullOrEmpty -Because 'the guard must never print an allow: VS Code would approve the call with it'
        $first.StdErr | Should -Match 'allowed by a Remote grant'
        Test-Path -LiteralPath $path | Should -Be $false -Because 'a used-up grant is deleted'
        $second.ExitCode | Should -Be 2 -Because $second.Output
    }

    It 'honors a count of two and no more' {
        $path = script:New-GrantFile -Root $script:root -Operation ([ordered]@{ 'gh pr create' = 2 })
        $payload = script:New-ToolPayload -Command 'gh pr create --fill'

        $first = script:Invoke-Guard -Payload $payload -GrantRoot $script:root
        $countAfterFirst = (script:Read-Grant -Path $path).operations.'gh pr create'
        $second = script:Invoke-Guard -Payload $payload -GrantRoot $script:root
        $third = script:Invoke-Guard -Payload $payload -GrantRoot $script:root

        $first.ExitCode | Should -Be 0 -Because $first.Output
        $countAfterFirst | Should -Be 1
        $second.ExitCode | Should -Be 0 -Because $second.Output
        Test-Path -LiteralPath $path | Should -Be $false -Because 'a used-up grant is deleted'
        $third.ExitCode | Should -Be 2 -Because $third.Output
    }

    It 'allows <Command> under a grant for <Phrase>' -ForEach $script:ghCase {
        $null = script:New-GrantFile -Root $script:root -Operation ([ordered]@{ $Phrase = 1 })

        $result = script:Invoke-Guard -Payload (script:New-ToolPayload -Command $Command) -GrantRoot $script:root

        $result.ExitCode | Should -Be 0 -Because $result.Output
    }

    It 'does not let a grant for <Phrase> cover another operation than <Command>' -ForEach $script:ghCase {
        $path = script:New-GrantFile -Root $script:root -Operation ([ordered]@{ 'git push' = 1 })
        $hashBefore = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash

        $result = script:Invoke-Guard -Payload (script:New-ToolPayload -Command $Command) -GrantRoot $script:root

        $result.ExitCode | Should -Be 2 -Because $result.Output
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash | Should -Be $hashBefore -Because 'a refused command must not consume a grant'
    }

    It 'allows a plain push such as <Command> under a git push grant' -ForEach $script:plainPushCase {
        $null = script:New-GrantFile -Root $script:root -Operation ([ordered]@{ 'git push' = 1 })

        $result = script:Invoke-Guard -Payload (script:New-ToolPayload -Command $Command) -GrantRoot $script:root

        $result.ExitCode | Should -Be 0 -Because $result.Output
    }

    It 'asks for git push --force, not git push, to allow <Command>' -ForEach $script:forceCase {
        $path = script:New-GrantFile -Root $script:root -Operation ([ordered]@{ 'git push' = 1 })
        $hashBefore = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash

        $plain = script:Invoke-Guard -Payload (script:New-ToolPayload -Command $Command) -GrantRoot $script:root

        $plain.ExitCode | Should -Be 2 -Because $plain.Output
        $plain.Output | Should -Match ([regex]::Escape('[[allow-remote: git push --force]]'))
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash | Should -Be $hashBefore

        $null = script:New-GrantFile -Root $script:root -Operation ([ordered]@{ 'git push --force' = 1 })
        $forced = script:Invoke-Guard -Payload (script:New-ToolPayload -Command $Command) -GrantRoot $script:root

        $forced.ExitCode | Should -Be 0 -Because $forced.Output
    }

    It 'does not let a git push --force grant allow a plain push' {
        $null = script:New-GrantFile -Root $script:root -Operation ([ordered]@{ 'git push --force' = 1 })

        $result = script:Invoke-Guard -Payload (script:New-ToolPayload -Command 'git push origin main') -GrantRoot $script:root

        $result.ExitCode | Should -Be 2 -Because $result.Output
    }

    It 'needs one use for each push in a command' {
        $path = script:New-GrantFile -Root $script:root -Operation ([ordered]@{ 'git push' = 1 })
        $hashBefore = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        $payload = script:New-ToolPayload -Command 'git push origin a; git push origin b'

        $short = script:Invoke-Guard -Payload $payload -GrantRoot $script:root

        $short.ExitCode | Should -Be 2 -Because $short.Output
        $short.Output | Should -Match ([regex]::Escape('[[allow-remote: git push x2]]'))
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash | Should -Be $hashBefore

        $null = script:New-GrantFile -Root $script:root -Operation ([ordered]@{ 'git push' = 2 })
        $enough = script:Invoke-Guard -Payload $payload -GrantRoot $script:root

        $enough.ExitCode | Should -Be 0 -Because $enough.Output
        Test-Path -LiteralPath $path | Should -Be $false
    }

    It 'consumes every operation of a command that needs two kinds, or none' {
        $path = script:New-GrantFile -Root $script:root -Operation ([ordered]@{ 'git push' = 1 })
        $hashBefore = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        $payload = script:New-ToolPayload -Command 'git push -u origin ai/x; gh pr create --fill'

        $partial = script:Invoke-Guard -Payload $payload -GrantRoot $script:root

        $partial.ExitCode | Should -Be 2 -Because $partial.Output
        $partial.Output | Should -Match ([regex]::Escape('[[allow-remote: git push, gh pr create]]')) -Because 'the next marker replaces the grant, so it must name everything the command needs'
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash | Should -Be $hashBefore

        $null = script:New-GrantFile -Root $script:root -Operation ([ordered]@{ 'git push' = 1; 'gh pr create' = 1 })
        $both = script:Invoke-Guard -Payload $payload -GrantRoot $script:root

        $both.ExitCode | Should -Be 0 -Because $both.Output
        Test-Path -LiteralPath $path | Should -Be $false
    }

    It 'never lifts a destructive local block: <Command>' -ForEach $script:destructiveCase {
        $path = script:New-GrantFile -Root $script:root -Operation ([ordered]@{ 'git push' = 1; 'gh api' = 1 })
        $hashBefore = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash

        $result = script:Invoke-Guard -Payload (script:New-ToolPayload -Command $Command) -GrantRoot $script:root

        $result.ExitCode | Should -Be 2 -Because $result.Output
        $result.Output | Should -Match ([regex]::Escape("Blocked by Copilot Atelier: this command $Operation"))
        $result.Output | Should -Not -Match 'allow-remote' -Because 'no marker lifts this block, so the reason must not suggest one'
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash | Should -Be $hashBefore
    }

    It 'ignores a grant for another session' {
        $null = script:New-GrantFile -Root $script:root -SessionId 'sess-a'

        $result = script:Invoke-Guard -Payload (script:New-ToolPayload -Command 'git push' -SessionId 'sess-b') -GrantRoot $script:root

        $result.ExitCode | Should -Be 2 -Because $result.Output
    }

    It 'gives session ids that only differ in unusable characters their own grants' {
        # Both used to become the same file name, so one session spent the other's grant (review F6).
        $null = script:Invoke-Grant -Payload (script:New-PromptPayload -Prompt '[[allow-remote: git push]]' -SessionId '../../x') -GrantRoot $script:root

        $other = script:Invoke-Guard -Payload (script:New-ToolPayload -Command 'git push' -SessionId '....x') -GrantRoot $script:root
        $own = script:Invoke-Guard -Payload (script:New-ToolPayload -Command 'git push' -SessionId '../../x') -GrantRoot $script:root

        $other.ExitCode | Should -Be 2 -Because $other.Output
        $own.ExitCode | Should -Be 0 -Because $own.Output
    }

    It 'gives two session ids that share their first 64 characters their own grants' {
        $first = ('a' * 64) + '-one'
        $second = ('a' * 64) + '-two'
        $null = script:Invoke-Grant -Payload (script:New-PromptPayload -Prompt '[[allow-remote: git push]]' -SessionId $first) -GrantRoot $script:root

        $other = script:Invoke-Guard -Payload (script:New-ToolPayload -Command 'git push' -SessionId $second) -GrantRoot $script:root

        $other.ExitCode | Should -Be 2 -Because $other.Output
    }

    It 'asks for 20 uses of <Phrase> for <Reason>, because it cannot count a command that repeats' -ForEach $script:repetitionCase {
        $path = script:New-GrantFile -Root $script:root -Operation ([ordered]@{ $Phrase = 1 })

        $short = script:Invoke-Guard -Payload (script:New-ToolPayload -Command $Command) -GrantRoot $script:root

        $short.ExitCode | Should -Be 2 -Because $short.Output
        $short.Output | Should -Match ([regex]::Escape("[[allow-remote: $Phrase x20]]"))
        $short.Output | Should -Match 'cannot count'
        $short.Output | Should -Match 'its own command' -Because 'the reason must tell the agent how to ask for a single use'
        (Test-Path -LiteralPath $path) | Should -Be $true -Because 'a refused command must not consume a grant'

        $path = script:New-GrantFile -Root $script:root -Operation ([ordered]@{ $Phrase = 20 })
        $full = script:Invoke-Guard -Payload (script:New-ToolPayload -Command $Command) -GrantRoot $script:root

        $full.ExitCode | Should -Be 0 -Because $full.Output
        (Test-Path -LiteralPath $path) | Should -Be $false -Because 'a command that repeats spends every use'
    }

    It 'does not read words in a commit message or a pull request as a loop: <Command>' -ForEach @(
        @{ Command = 'git commit -m "fix: for (x) while (y) do { z } foreach (q)"; git push origin main'; Phrase = 'git push' }
        @{ Command = 'gh pr create --title "Fix function parsing" --body "do the work while the build runs" --fill'; Phrase = 'gh pr create' }
        @{ Command = 'gh pr create --title "Use for each loop in docs" --fill'; Phrase = 'gh pr create' }
        @{ Command = 'gh pr create --title "x" --body "function Get-Thing() { return 1 }" --fill'; Phrase = 'gh pr create' }
        @{ Command = "gh pr create --title x --body 'for (`$i = 0; `$i -lt 3; `$i++) { work }' --fill"; Phrase = 'gh pr create' }
        @{ Command = 'gh issue comment 5 --body "do { work } while ($false)"'; Phrase = 'gh issue comment' }
        @{ Command = 'gh pr create --title "x" --body "1..5 | ForEach-Object { work } and (1..3).ForEach({ x })" --fill'; Phrase = 'gh pr create' }
        @{ Command = 'gh pr create --title "retry until it works" --body "watch the logs while the job runs; schtasks and Register-ScheduledTask are not used" --fill'; Phrase = 'gh pr create' }
        @{ Command = 'git commit -m "while loop, until loop, class Foo { }, trap { }"; git push origin main'; Phrase = 'git push' }
        @{ Command = 'gh issue comment 5 --body "{ not a script block } and @{ a = 1 } and . $x and & $y"'; Phrase = 'gh issue comment' }
        @{ Command = 'gh pr create --title "built at $(Get-Date -Format s)" --fill'; Phrase = 'gh pr create' }
        @{ Command = '$h = @{ a = 1 }; gh pr create --title x --fill'; Phrase = 'gh pr create' }
    ) {
        $path = script:New-GrantFile -Root $script:root -Operation ([ordered]@{ $Phrase = 1 })

        $result = script:Invoke-Guard -Payload (script:New-ToolPayload -Command $Command) -GrantRoot $script:root

        $result.ExitCode | Should -Be 0 -Because $result.Output
        (Test-Path -LiteralPath $path) | Should -Be $false
    }

    It 'ignores a grant copied to the file name of another session' {
        $path = script:New-GrantFile -Root $script:root -SessionId 'sess-a'
        Copy-Item -LiteralPath $path -Destination (Join-Path -Path $script:root -ChildPath 'grant-sess-b.json')

        $result = script:Invoke-Guard -Payload (script:New-ToolPayload -Command 'git push' -SessionId 'sess-b') -GrantRoot $script:root

        $result.ExitCode | Should -Be 2 -Because 'the grant names its own session inside the file'
    }

    It 'blocks when the payload names no session, even with a grant on disk' {
        $null = script:New-GrantFile -Root $script:root -SessionId 'sess-1'

        $result = script:Invoke-Guard -Payload (script:New-ToolPayload -Command 'git push' -SessionId $null) -GrantRoot $script:root

        $result.ExitCode | Should -Be 2 -Because $result.Output
    }

    It 'blocks under a grant that <Why>' -ForEach $script:invalidGrantCase {
        $path = script:New-GrantFile -Root $script:root
        if ($null -ne $Content) {
            [IO.File]::WriteAllText($path, $Content)
        } else {
            $grant = [ordered]@{}
            foreach ($property in (script:Read-Grant -Path $path).PSObject.Properties) {
                $grant[$property.Name] = $property.Value
            }

            $now = script:Get-UnixSecond
            if ($Remove) {
                $grant.Remove($Remove)
            }

            foreach ($name in @(if ($Patch) { $Patch.Keys })) {
                $value = $Patch[$name]
                # A time in the table is an offset from now.
                if (($name -in @('issuedAt', 'expiresAt')) -and ($value -is [int])) {
                    $value = $now + $value
                }

                $grant[$name] = $value
            }

            [IO.File]::WriteAllText($path, ($grant | ConvertTo-Json -Depth 5))
        }

        $result = script:Invoke-Guard -Payload (script:New-ToolPayload -Command 'git push') -GrantRoot $script:root

        $result.ExitCode | Should -Be 2 -Because $result.Output
    }

    It 'blocks when the grant file is locked by another process' {
        $path = script:New-GrantFile -Root $script:root
        $stream = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        try {
            $result = script:Invoke-Guard -Payload (script:New-ToolPayload -Command 'git push') -GrantRoot $script:root
        } finally {
            $stream.Dispose()
        }

        $result.ExitCode | Should -Be 2 -Because 'a grant that cannot be consumed atomically is not honored'
    }

    It 'lets exactly one of several concurrent pushes use a single grant' {
        $path = script:New-GrantFile -Root $script:root
        $payload = script:New-ToolPayload -Command 'git push origin main'

        $started = 1..4 | ForEach-Object -Process {
            script:Start-HookProcess -ScriptPath $script:guardScript -Payload $payload -ArgumentList @('-GrantRoot', ('"{0}"' -f $script:root))
        }
        $results = $started | ForEach-Object -Process { script:Wait-HookProcess -Started $_ }

        @($results | Where-Object -Property ExitCode -EQ -Value 0).Count | Should -Be 1 -Because (($results | ForEach-Object -Process { $_.Output }) -join ' | ')
        @($results | Where-Object -Property ExitCode -EQ -Value 2).Count | Should -Be 3
        Test-Path -LiteralPath $path | Should -Be $false
    }

    It 'ignores COPILOT_ATELIER_ALLOW_REMOTE in the hook environment' {
        $result = script:Invoke-Guard -Payload (script:New-ToolPayload -Command 'git push origin main') -Environment @{ COPILOT_ATELIER_ALLOW_REMOTE = '1' }

        $result.ExitCode | Should -Be 2 -Because 'the override was removed (Decision 0016, 2026-10-12): it could turn the guard off for a whole VS Code instance'
        $result.Output | Should -Not -Match 'allowed by'
    }

    It 'does not treat marker text in the command as a grant' {
        $result = script:Invoke-Guard -Payload (script:New-ToolPayload -Command 'git push origin main # [[allow-remote: git push]]') -GrantRoot $script:root

        $result.ExitCode | Should -Be 2 -Because $result.Output
    }

    It 'does not treat a variable set in the command as a grant' {
        $command = '$env:COPILOT_ATELIER_ALLOW_REMOTE = ''1''; git push origin main'

        $result = script:Invoke-Guard -Payload (script:New-ToolPayload -Command $command) -GrantRoot $script:root

        $result.ExitCode | Should -Be 2 -Because $result.Output
    }

    It 'does not honor a grant for a payload it could not inspect completely' {
        <#
            A payload nested past the walk's depth is scanned as raw text, which
            errs toward blocking. A grant must not turn that block into an allow.
        #>
        $null = script:New-GrantFile -Root $script:root
        $commandJson = [ordered]@{ command = 'git push origin main' } | ConvertTo-Json -Compress
        $depth = 70
        $payload = '{"hook_event_name":"PreToolUse","session_id":"sess-1","tool_name":"mcp_tool","tool_input":' +
            ('{"a":' * $depth) + $commandJson + ('}' * $depth) + '}'

        $result = script:Invoke-Guard -Payload $payload -GrantRoot $script:root

        $result.ExitCode | Should -Be 2 -Because $result.Output
    }

    It 'tells the model which marker to ask the user for' {
        $result = script:Invoke-Guard -Payload (script:New-ToolPayload -Command 'git push origin main') -GrantRoot $script:root

        $result.ExitCode | Should -Be 2 -Because $result.Output
        $result.StdErr | Should -Match '\ABlocked by Copilot Atelier: this command pushes to a git remote'
        $result.Output | Should -Match ([regex]::Escape('[[allow-remote: git push]]'))
        $result.Output | Should -Match 'only a message from the user'
        $result.Output | Should -Match 'never write or change one yourself'
        $result.Output | Should -Match 'fenced code block in your reply' -Because 'the user can still run the command in their own terminal'
        $result.Output | Should -Match 'in their own terminal'
        $result.Output | Should -Not -Match 'COPILOT_ATELIER_ALLOW_REMOTE'
        $decision = ([regex]::Match($result.StdOut, '\{.*\}')).Value | ConvertFrom-Json
        $decision.PSObject.Properties.Name | Should -Be @('permissionDecision', 'permissionDecisionReason')
        $decision.permissionDecision | Should -BeExactly 'deny'
    }

    It 'tells the model a block cannot be lifted when no marker could' {
        $result = script:Invoke-Guard -Payload (script:New-ToolPayload -Command 'git reset --hard HEAD~1') -GrantRoot $script:root

        $result.ExitCode | Should -Be 2 -Because $result.Output
        $result.Output | Should -Match 'No Grant marker lifts this block'
        $result.Output | Should -Match 'fenced code block in your reply'
        $result.Output | Should -Not -Match 'COPILOT_ATELIER_ALLOW_REMOTE'
    }

    It 'consumes a grant under Windows PowerShell as well' -Skip:(-not $script:windowsPowerShellAvailable) {
        $path = script:New-GrantFile -Root $script:root -Operation ([ordered]@{ 'git push' = 2 })
        $payload = script:New-ToolPayload -Command 'git push origin main'

        $first = script:Invoke-Guard -Payload $payload -GrantRoot $script:root -PowerShellPath $script:windowsPowerShellPath

        $first.ExitCode | Should -Be 0 -Because $first.Output
        (script:Read-Grant -Path $path).operations.'git push' | Should -Be 1
    }
}

Describe 'Block-RemoteMutation repetition under Windows PowerShell' -Tag 'Unit' -Skip:(-not $script:windowsPowerShellAvailable) {
    <#
        Windows PowerShell 5.1 does not know && and ||, so it reads such a text as written, without a
        syntax tree; a brace in text that was not read counts as a script block that may run again.
    #>
    BeforeEach {
        $script:root = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
    }

    It 'asks for 20 uses of git push for <Reason>' -ForEach @(
        @{ Reason = 'a script block after && that it cannot parse'; Command = 'git status && 1..3 | Sort-Object { git push origin main }' }
        @{ Reason = 'a script block that it can parse'; Command = '1..3 | Sort-Object { git push origin main }' }
        @{ Reason = 'a shell until loop'; Command = 'until git push origin main; do sleep 5; done' }
    ) {
        $path = script:New-GrantFile -Root $script:root -Operation ([ordered]@{ 'git push' = 1 })

        $short = script:Invoke-Guard -Payload (script:New-ToolPayload -Command $Command) -GrantRoot $script:root -PowerShellPath $script:windowsPowerShellPath

        $short.ExitCode | Should -Be 2 -Because $short.Output
        $short.Output | Should -Match ([regex]::Escape('[[allow-remote: git push x20]]'))
        (Test-Path -LiteralPath $path) | Should -Be $true -Because 'a refused command must not consume a grant'
    }

    It 'lets a grant of one use carry a plain push after && that it cannot parse' {
        $path = script:New-GrantFile -Root $script:root -Operation ([ordered]@{ 'git push' = 1 })

        $result = script:Invoke-Guard -Payload (script:New-ToolPayload -Command 'git status && git push origin main') -GrantRoot $script:root -PowerShellPath $script:windowsPowerShellPath

        $result.ExitCode | Should -Be 0 -Because $result.Output
        (Test-Path -LiteralPath $path) | Should -Be $false
    }
}

Describe 'Add-RemoteGrant and Block-RemoteMutation together' -Tag 'Unit' {
    BeforeEach {
        $script:root = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
    }

    It 'lets a marker in the prompt authorize one push and the next prompt end it' {
        $payload = script:New-ToolPayload -Command 'git push -u origin ai/x'
        $before = script:Invoke-Guard -Payload $payload -GrantRoot $script:root
        $null = script:Invoke-Grant -Payload (script:New-PromptPayload -Prompt 'push it [[allow-remote: git push]]') -GrantRoot $script:root
        $granted = script:Invoke-Guard -Payload $payload -GrantRoot $script:root
        $again = script:Invoke-Guard -Payload $payload -GrantRoot $script:root
        $null = script:Invoke-Grant -Payload (script:New-PromptPayload -Prompt 'push it [[allow-remote: git push]]') -GrantRoot $script:root
        $null = script:Invoke-Grant -Payload (script:New-PromptPayload -Prompt 'never mind') -GrantRoot $script:root
        $afterNextPrompt = script:Invoke-Guard -Payload $payload -GrantRoot $script:root

        $before.ExitCode | Should -Be 2 -Because $before.Output
        $granted.ExitCode | Should -Be 0 -Because $granted.Output
        $again.ExitCode | Should -Be 2 -Because $again.Output
        $afterNextPrompt.ExitCode | Should -Be 2 -Because $afterNextPrompt.Output
    }

    It 'derives the same grant file for the session id <SessionId> in both scripts' -ForEach @(
        @{ SessionId = 'a/b\c:d' }
        @{ SessionId = '../../escape' }
        @{ SessionId = ('x' * 80) }
        @{ SessionId = '8B2534F0-ce51-43b9-aa16-c7c20431219d' }
    ) {
        $null = script:Invoke-Grant -Payload (script:New-PromptPayload -Prompt '[[allow-remote: gh pr create]]' -SessionId $SessionId) -GrantRoot $script:root

        $result = script:Invoke-Guard -Payload (script:New-ToolPayload -Command 'gh pr create --fill' -SessionId $SessionId) -GrantRoot $script:root

        $result.ExitCode | Should -Be 0 -Because $result.Output
    }

    It 'keeps the list of grantable operations identical in both scripts' {
        function Get-OperationList {
            param(
                [Parameter(Mandatory)]
                [string]$Path
            )

            $errors = $null
            $tokens = $null
            $ast = [Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
            $errors | Should -BeNullOrEmpty
            $assignment = $ast.Find({
                    param($node)
                    $node -is [Management.Automation.Language.AssignmentStatementAst] -and
                    $node.Left -is [Management.Automation.Language.VariableExpressionAst] -and
                    $node.Left.VariablePath.UserPath -eq 'grantableOperation'
                }, $true)
            $assignment | Should -Not -BeNullOrEmpty -Because "$Path must define `$grantableOperation"
            @($assignment.Right.FindAll({ param($node) $node -is [Management.Automation.Language.StringConstantExpressionAst] }, $true) |
                ForEach-Object -Process { $_.Value })
        }

        $fromGuard = Get-OperationList -Path $script:guardScript
        $fromHook = Get-OperationList -Path $script:grantScript

        $fromGuard | Should -Not -BeNullOrEmpty
        $fromGuard | Should -Contain 'git push'
        $fromGuard | Should -Contain 'git push --force'
        $fromGuard | Should -Contain 'gh pr create'
        $fromGuard | Should -Contain 'gh api'
        $fromGuard | Should -Not -Contain 'git reset --hard'
        ($fromHook | Sort-Object) | Should -Be ($fromGuard | Sort-Object)
    }
}

Describe 'Hook configuration for the Remote grant' -Tag 'Unit' {
    BeforeAll {
        $script:hookConfig = Get-Content -LiteralPath $script:hookConfigPath -Raw | ConvertFrom-Json
    }

    It 'declares a UserPromptSubmit hook with the three launchers and a timeout' {
        $entries = @($script:hookConfig.hooks.UserPromptSubmit)

        $entries.Count | Should -Be 1
        $entries[0].type | Should -BeExactly 'command'
        $entries[0].timeout | Should -Be 20
        foreach ($launcher in 'command', 'windows', 'powershell') {
            $entries[0].$launcher | Should -Match 'scripts/Add-RemoteGrant\.ps1' -Because "the $launcher launcher must run the grant hook"
        }
    }

    It 'never lets a failing grant hook block or deny the user''s prompt' {
        $entry = @($script:hookConfig.hooks.UserPromptSubmit)[0]

        foreach ($launcher in 'command', 'windows', 'powershell') {
            $entry.$launcher | Should -Match 'exit 1'
            $entry.$launcher | Should -Not -Match 'exit 2' -Because 'exit 2 blocks the prompt in VS Code'
        }
    }
}
