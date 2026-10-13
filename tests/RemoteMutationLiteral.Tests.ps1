<#
    What Block-RemoteMutation treats as an invocation of a blocked command.

    The guard used to match the whole command text, string literals included, so a
    commit message built in a here-string that quoted a blocked command was denied
    (the NTFSSecurity session of 2026-10-04, evidence item 2). It now decides on
    the parsed command where that is provably safe: the text of a string literal
    that only feeds a data-writing cmdlet, a variable, or a commit message is not
    scanned. Everything it cannot prove inert stays scanned as before: indirect
    execution, text that does not parse, and the arguments of any other program.

    Each case runs the real guard in a child process, the way a host starts it.
#>

BeforeDiscovery {
    $newline = "`n"
    $script:isWindowsPlatform = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
    $script:windowsPowerShellAvailable = $script:isWindowsPlatform -and
        (Test-Path -LiteralPath (Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'))

    # A commit message that quotes the command the agent had just been denied,
    # built in a here-string and committed from a file: evidence item 2.
    $evidenceTwo = @(
        '$message = @'''
        'docs: explain the guard'
        ''
        'The agent ran gh pr create -R raandree/NTFSSecurity --base master and was denied.'
        '''@'
        'Set-Content -LiteralPath msg.txt -Value $message'
        'git add -A'
        'git commit -F msg.txt'
    ) -join $newline

    $script:allowedCase = @(
        @{ Reason = 'writes the text with Write-Output'; Command = "Write-Output 'probe: git push origin main is only text here'" }
        @{ Reason = 'writes double-quoted text with Write-Output'; Command = 'Write-Output "gh pr create --fill"' }
        @{ Reason = 'writes text with Write-Host'; Command = "Write-Host 'run git push later'" }
        @{ Reason = 'echoes the text'; Command = "echo 'git push origin main'" }
        @{ Reason = 'builds a commit message in a here-string and commits it from a file'; Command = $evidenceTwo }
        @{
            Reason = 'keeps a here-string in a variable and writes it out'
            Command = @('$text = @"', 'Remember: git push needs a Remote grant.', '"@', 'Write-Output $text') -join $newline
        }
        @{
            Reason = 'keeps a here-string with a variable in it and writes it out'
            Command = @('$text = @"', 'git push $remote is blocked', '"@', 'Write-Output $text') -join $newline
        }
        @{ Reason = 'saves a note with Set-Content'; Command = "Set-Content -Path notes.md -Value 'Never run git push without asking.'" }
        @{ Reason = 'appends a note with Add-Content'; Command = 'Add-Content -Path notes.md -Value "gh issue comment 42 --body hi"' }
        @{ Reason = 'pipes a literal into Set-Content'; Command = "'git push origin main' | Set-Content notes.txt" }
        @{ Reason = 'pipes a here-string into Out-File'; Command = @('@''', 'git push origin main', '''@ | Out-File -FilePath plan.txt') -join $newline }
        @{ Reason = 'searches for the text'; Command = "Select-String -Path notes.md -Pattern 'git push'" }
        @{ Reason = 'writes a test fixture that quotes a blocked command'; Command = @('Set-Content -Path x.Tests.ps1 -Value @''', 'It ''pushes'' { git push origin main }', '''@') -join $newline }
        @{ Reason = 'keeps the lines in an array and writes them out'; Command = @('$lines = @(''git push'', ''gh pr create'')', '$lines | Set-Content steps.txt') -join $newline }
        @{ Reason = 'mixes a quoted mention with other local commands'; Command = "git status; Write-Output 'git push'; git log --oneline" }
        @{ Reason = 'interpolates a date into a quoted mention'; Command = 'Write-Output "git push at $(Get-Date)"' }
        @{ Reason = 'commits with a message that quotes a blocked command'; Command = 'git commit -m "docs: explain why gh pr create was denied"' }
        @{ Reason = 'commits with a message that names a hook bypass'; Command = 'git commit -m "docs: never pass --no-verify"' }
        @{ Reason = 'commits with a message that quotes git push'; Command = "git commit -am 'revert: git push mistake'" }
        @{ Reason = 'commits with a second message paragraph that quotes a blocked command'; Command = 'git commit -m "fix: x" -m "The agent ran git push."' }
        @{ Reason = 'tags with a message that quotes a blocked command'; Command = 'git tag -a v1.0.0 -m "release: git push notes"' }

        # Flows that treat a held literal as data, which the data-flow rule must keep allowing.
        @{ Reason = 'commits with a message held in a variable'; Command = "`$msg = 'docs: explain why gh pr create was denied'; git commit -m `$msg" }
        @{ Reason = 'commits with a message held in a variable inside a string'; Command = "`$msg = 'docs: explain why gh pr create was denied'; git commit -m `"`$msg`"" }
        @{ Reason = 'writes a variable out through the pipeline and commits it from a file'; Command = "`$msg = 'docs: gh pr create'; `$msg | Set-Content m.txt; git commit -F m.txt" }
        @{ Reason = 'writes a variable out with File.WriteAllText'; Command = "`$msg = 'docs: gh pr create'; [System.IO.File]::WriteAllText('m.txt', `$msg)" }
        @{ Reason = 'assigns a literal that nothing uses'; Command = "`$x = 'git push origin main'" }
        @{ Reason = 'reassigns the variable before it is written out'; Command = "`$a = 'git push'; `$a = 'other'; Write-Output `$a" }
        @{ Reason = 'uses the module-qualified name of Write-Output'; Command = "Microsoft.PowerShell.Utility\Write-Output 'git push origin main'" }
        @{ Reason = 'keeps a typed variable and writes it out'; Command = "[string]`$note = 'never run git push unasked'; Write-Output `$note" }

        # Writes whose target the guard can read: a literal path, or a variable that is only ever assigned one.
        @{ Reason = 'writes to a path held in a variable that is assigned a literal'; Command = "`$p = 'msg.txt'; Set-Content -LiteralPath `$p -Value 'docs: gh pr create'" }
        @{ Reason = 'writes to a typed path variable'; Command = "[string]`$p = '.\notes\msg.txt'; 'git push notes' | Out-File -FilePath `$p" }
        @{ Reason = 'writes to a literal path given by name'; Command = "New-Item -ItemType File -Path . -Name n.txt -Value 'git push notes'" }
        @{ Reason = 'appends to a path on a drive letter'; Command = "Add-Content -Path C:\work\notes.md -Value 'gh issue comment 42'" }
        @{ Reason = 'writes a list of literal paths'; Command = "Set-Content -Path .\a.md, .\b.md -Value 'git push is blocked'" }
        @{ Reason = 'writes after changing into a literal folder'; Command = "Set-Location .\docs; Set-Content notes.md 'git push is blocked'" }
        @{ Reason = 'writes through a here-string held in a variable to a literal path'; Command = (@('$body = @''', 'Notes: gh pr create is blocked.', '''@', 'Set-Content -Path notes.md -Value $body') -join "`n") }

        # Parameter spellings that PowerShell accepts and the closed table of the four writers knows.
        @{ Reason = 'names the path by a prefix of -LiteralPath'; Command = "Set-Content -Lit notes.md -Value 'git push is blocked'" }
        @{ Reason = 'names the path by the PSPath alias'; Command = "Set-Content -PSPath notes.md -Value 'git push is blocked'" }
        @{ Reason = 'names the path by the LP alias and a literal'; Command = "Add-Content -LP notes.md -Value 'git push is blocked'" }
        @{ Reason = 'gives a writer switches, an encoding, and common parameters'; Command = "Set-Content -Path notes.md -Value 'git push is blocked' -Encoding utf8 -NoNewline -Force -ErrorAction Stop -WhatIf:`$false" }
        @{ Reason = 'gives a writer common parameter aliases'; Command = "Add-Content -ea Stop -Path notes.md -Value 'gh issue comment 42' -wi" }
        @{ Reason = 'gives a writer -WarningAction by its alias, which starts like -WarningVariable'; Command = "Set-Content -Path notes.md -Value 'git push is blocked' -wa SilentlyContinue -infa Ignore" }
        @{ Reason = 'writes with Out-File and the Path alias of -FilePath'; Command = "'git push notes' | Out-File -Path plan.txt -Encoding utf8 -Append -NoClobber" }
        @{ Reason = 'creates an item with the Type alias'; Command = "New-Item -Type File -Path notes.md -Value 'git push is blocked' -Force" }
        @{ Reason = 'moves into a literal folder and back'; Command = "Push-Location .\docs; Set-Content notes.md 'git push is blocked'; Pop-Location" }
        @{ Reason = 'writes a workflow file, whose folder only looks like git control'; Command = "Set-Content -Path .github/workflows/ci.yml -Value 'run: git push is blocked'" }
        @{ Reason = 'writes .gitignore'; Command = "Add-Content -Path .gitignore -Value 'notes about git push'" }
        @{ Reason = 'writes into a folder of a bare repository name'; Command = "Set-Content -Path backup.git/NOTES -Value 'git push is blocked'" }
        @{ Reason = 'writes a notes file whose name only mentions a profile'; Command = "Set-Content -Path notes-profile.md -Value 'git push is blocked'" }
        @{ Reason = 'writes a file in a folder whose name only starts like Startup'; Command = "Set-Content -Path docs/startup-notes/readme.md -Value 'git push is blocked'" }
        @{ Reason = 'writes a file whose name only starts like .bashrc'; Command = "Set-Content -Path .bashrc.md -Value 'git push is blocked'" }
        @{ Reason = 'writes the VS Code settings, which run nothing'; Command = "Set-Content -Path .vscode/settings.json -Value 'git push is blocked'" }
    )

    $script:blockedCase = @(
        @{ Reason = 'pushes after a semicolon'; Command = 'git status; git push origin main'; Operation = 'pushes to a git remote' }
        @{ Reason = 'pushes after an ampersand pair'; Command = 'git add . && git push'; Operation = 'pushes to a git remote' }
        @{ Reason = 'pushes after a single ampersand'; Command = 'git status & git push'; Operation = 'pushes to a git remote' }
        @{ Reason = 'pushes through the call operator'; Command = '& git push origin main'; Operation = 'pushes to a git remote' }
        @{ Reason = 'pushes through the call operator with a quoted name'; Command = "& 'git' push origin main"; Operation = 'pushes to a git remote' }
        @{ Reason = 'pushes through git.exe'; Command = '& "git.exe" push origin main'; Operation = 'pushes to a git remote' }
        @{ Reason = 'creates a pull request through gh.exe'; Command = 'gh.exe pr create --fill'; Operation = 'mutates a GitHub remote resource' }
        @{ Reason = 'mentions a push and then really pushes'; Command = "Write-Output 'git push'; git push origin main"; Operation = 'pushes to a git remote' }
        @{ Reason = 'pushes after a commit with a harmless message'; Command = 'git commit -m "docs: x"; git push'; Operation = 'pushes to a git remote' }
        @{ Reason = 'pushes from inside a function'; Command = 'function Publish { git push origin main }; Publish'; Operation = 'pushes to a git remote' }
        @{ Reason = 'pushes from inside a conditional'; Command = 'if ($true) { git push }'; Operation = 'pushes to a git remote' }
        @{ Reason = 'pushes from inside a script block'; Command = 'Invoke-Command -ScriptBlock { git push }'; Operation = 'pushes to a git remote' }
        @{ Reason = 'pushes through a command substitution in a string'; Command = 'Write-Output "done: $(git push origin main)"'; Operation = 'pushes to a git remote' }
        @{ Reason = 'pushes through a command substitution in a here-string'; Command = @('$text = @"', '$(git push origin main)', '"@') -join "`n"; Operation = 'pushes to a git remote' }
        @{ Reason = 'bypasses hooks in a real flag'; Command = 'git commit --no-verify -m "x"'; Operation = 'bypasses repository hooks' }
        @{ Reason = 'bypasses hooks next to a message'; Command = 'git commit -m "x" --no-verify'; Operation = 'bypasses repository hooks' }
        @{ Reason = 'evaluates a string with Invoke-Expression'; Command = "Invoke-Expression 'git push origin main'"; Operation = 'pushes to a git remote' }
        @{ Reason = 'evaluates a string with iex'; Command = 'iex "git push origin main"'; Operation = 'pushes to a git remote' }
        @{ Reason = 'evaluates a variable with Invoke-Expression'; Command = "`$cmd = 'git push origin main'; Invoke-Expression `$cmd"; Operation = 'pushes to a git remote' }
        @{ Reason = 'calls a computed name'; Command = "`$cmd = 'git push origin main'; & `$cmd"; Operation = 'pushes to a git remote' }
        @{ Reason = 'dot-sources a computed name'; Command = "`$cmd = 'git push origin main'; . `$cmd"; Operation = 'pushes to a git remote' }
        @{ Reason = 'builds a script block from a string'; Command = "[scriptblock]::Create('git push origin main').Invoke()"; Operation = 'pushes to a git remote' }
        @{ Reason = 'runs a string through a nested pwsh -Command'; Command = 'pwsh -NoProfile -Command "git push origin main"'; Operation = 'pushes to a git remote' }
        @{ Reason = 'runs a string through a nested powershell -c'; Command = "powershell -c 'git push origin main'"; Operation = 'pushes to a git remote' }
        @{ Reason = 'runs a string through cmd /c'; Command = 'cmd /c "git push origin main"'; Operation = 'pushes to a git remote' }
        @{ Reason = 'runs a string through bash -c'; Command = "bash -c 'git push origin main'"; Operation = 'pushes to a git remote' }
        @{ Reason = 'runs a string through sh -c'; Command = 'sh -c "git push"'; Operation = 'pushes to a git remote' }
        @{ Reason = 'runs a string through node -e'; Command = 'node -e "require(''child_process'').execSync(''git push'')"'; Operation = 'pushes to a git remote' }
        @{ Reason = 'pipes text into bash'; Command = "Write-Output 'git push origin main' | bash"; Operation = 'pushes to a git remote' }
        @{ Reason = 'pipes text into pwsh'; Command = "echo 'git push origin main' | pwsh -NoProfile -Command -"; Operation = 'pushes to a git remote' }
        @{ Reason = 'pipes a variable text into sh'; Command = "`$m = 'git push origin main'; `$m | sh"; Operation = 'pushes to a git remote' }
        @{ Reason = 'hides a push in a backtick command substitution'; Command = 'Write-Output "`git push`"'; Operation = 'pushes to a git remote' }
        @{ Reason = 'leaves a string unterminated'; Command = "Write-Output 'git push origin main"; Operation = 'pushes to a git remote' }
        @{ Reason = 'leaves a command unparseable'; Command = 'git push origin main )'; Operation = 'pushes to a git remote' }
        @{ Reason = 'starts a process for git with a string argument list'; Command = "Start-Process git -ArgumentList 'push origin main'"; Operation = 'pushes to a git remote' }
        @{ Reason = 'starts a process for git with an array argument list'; Command = "Start-Process -FilePath git.exe -ArgumentList push,origin,main"; Operation = 'pushes to a git remote' }
        @{ Reason = 'starts a process for gh with an argument list'; Command = "Start-Process gh -ArgumentList 'pr','create','--fill'"; Operation = 'mutates a GitHub remote resource' }
        @{ Reason = 'starts a process for git with an argument list it cannot read'; Command = 'Start-Process git -ArgumentList $arguments'; Operation = 'launches git or gh through a command it cannot read' }
        @{ Reason = 'starts a process for gh through a variable'; Command = 'Start-Process -FilePath gh -ArgumentList $arguments -Wait'; Operation = 'launches git or gh through a command it cannot read' }

        # Review of 2026-10-13, F1: a provider drive defines a function that the same command then runs.
        @{ Reason = 'defines a function through the Function drive variable'; Command = "`$function:deploy = 'git push origin main'; deploy"; Operation = 'pushes to a git remote' }
        @{ Reason = 'defines a function through a braced Function drive variable'; Command = "`${function:deploy} = 'git push --force'; deploy"; Operation = 'pushes to a git remote' }
        @{ Reason = 'defines a function with Set-Content on the Function drive'; Command = "Set-Content -Path function:deploy -Value 'git push origin main'; deploy"; Operation = 'pushes to a git remote' }
        @{ Reason = 'defines a function with New-Item on the Function drive'; Command = "New-Item -Path function:deploy -Value 'git push origin main'; deploy"; Operation = 'pushes to a git remote' }
        @{ Reason = 'defines a function through a drive path held in a variable'; Command = "`$path = 'function:deploy'; Set-Content -Path `$path -Value 'git push origin main'; deploy"; Operation = 'pushes to a git remote' }

        # A name that echo, Write-Output, and the like can no longer be trusted to carry.
        @{ Reason = 'redefines echo with Set-Alias and then runs a literal through it'; Command = "Set-Alias echo Invoke-Expression; echo 'git push origin main'"; Operation = 'pushes to a git remote' }
        @{ Reason = 'redefines Write-Output with New-Alias'; Command = "New-Alias -Name Write-Output -Value iex; Write-Output 'git push origin main'"; Operation = 'pushes to a git remote' }
        @{ Reason = 'redefines echo through the sal alias'; Command = "sal echo iex; echo 'git push origin main'"; Operation = 'pushes to a git remote' }
        @{ Reason = 'redefines echo through the Alias drive'; Command = "Set-Item Alias:echo Invoke-Expression; echo 'git push origin main'"; Operation = 'pushes to a git remote' }
        @{ Reason = 'redefines echo through the Function drive'; Command = "Set-Item function:echo 'Invoke-Expression `$args'; echo 'git push origin main'"; Operation = 'pushes to a git remote' }
        @{ Reason = 'redefines echo as a function that runs a script file'; Command = "function echo { `"`$args`" | Out-File x.ps1; .\x.ps1 }; echo 'git push origin main'"; Operation = 'pushes to a git remote' }

        # A path or an extension names a program that only looks like an inert command.
        @{ Reason = 'calls a script that is named like Write-Output'; Command = ".\write-output.ps1 'git push origin main'"; Operation = 'pushes to a git remote' }
        @{ Reason = 'calls a program whose file name looks like echo'; Command = "C:\tools\echo.cmd 'git push origin main'"; Operation = 'pushes to a git remote' }
        @{ Reason = 'pipes a literal into a script that is named like Set-Content'; Command = "'git push origin main' | .\set-content.ps1"; Operation = 'pushes to a git remote' }
        @{ Reason = 'calls a script that is named like git and gives it a message'; Command = ".\git.ps1 commit -m 'git push origin main'"; Operation = 'pushes to a git remote' }
        @{ Reason = 'calls a wrapper that is named like git.cmd'; Command = "C:\tools\git.cmd commit -m 'git push origin main'"; Operation = 'pushes to a git remote' }

        # A --message= value is one token, and what is expanded inside it runs.
        @{ Reason = 'runs a command substitution inside a --message= value'; Command = 'git commit --message="$(git push origin main)"'; Operation = 'pushes to a git remote' }
        @{ Reason = 'runs a pull request inside a --message= value'; Command = 'git commit --message="x $(gh pr create --fill) y"'; Operation = 'mutates a GitHub remote resource' }

        # An assigned literal is data only when everything it flows into treats it as data.
        @{ Reason = 'hands an assigned literal to schtasks'; Command = "`$x = 'git push origin main'; schtasks /create /tn t /tr `$x /sc once /st 00:00"; Operation = 'pushes to a git remote' }
        @{ Reason = 'hands an assigned literal to wmic'; Command = "`$x = 'git push origin main'; wmic process call create `$x"; Operation = 'pushes to a git remote' }
        @{ Reason = 'hands an assigned literal to Process.Start'; Command = "`$x = 'git push origin main'; [Diagnostics.Process]::Start('cmd', `"/c `$x`")"; Operation = 'pushes to a git remote' }
        @{ Reason = 'hands an assigned literal to a COM object'; Command = "`$x = 'git push origin main'; (New-Object -ComObject WScript.Shell).Run(`$x)"; Operation = 'pushes to a git remote' }
        @{ Reason = 'hands an assigned literal to an unknown program'; Command = "`$x = 'git push origin main'; foo `$x"; Operation = 'pushes to a git remote' }
        @{ Reason = 'copies an assigned literal to a second variable that is then used'; Command = "`$x = 'git push origin main'; `$y = `$x; foo `$y"; Operation = 'pushes to a git remote' }
        @{ Reason = 'reads an assigned literal back with Get-Variable'; Command = "`$x = 'git push origin main'; Get-Variable x -ValueOnly | foo"; Operation = 'pushes to a git remote' }
        @{ Reason = 'splats an assigned literal'; Command = "`$x = @('git push origin main'); foo @x"; Operation = 'pushes to a git remote' }
        @{ Reason = 'uses an assigned literal in an expression'; Command = "`$x = 'git push origin main'; (`$x + ' --quiet') | foo"; Operation = 'pushes to a git remote' }

        # Review of 2026-10-13, F2: the stop-parsing token hides the subcommand from every rule.
        @{ Reason = 'hides a push behind the stop-parsing token'; Command = 'git --% push origin main'; Operation = 'pushes to a git remote' }
        @{ Reason = 'hides a hard reset behind the stop-parsing token'; Command = 'git --% reset --hard HEAD~1'; Operation = 'discards work with a hard reset' }
        @{ Reason = 'hides a pull request behind the stop-parsing token'; Command = 'gh --% pr create --fill'; Operation = 'mutates a GitHub remote resource' }

        # Review of 2026-10-13, second pass, G1: the target of a write is computed, so the guard cannot tell
        # whether it is a file or the Function drive. An unknown target is not a known-inert target.
        @{ Reason = 'writes a function to a drive name built with +'; Command = "New-Item -Path ('func' + 'tion:deploy') -Value 'git push origin main'; deploy"; Operation = 'pushes to a git remote' }
        @{ Reason = 'writes to a drive name built with + using Set-Content'; Command = "Set-Content -Path ('func' + 'tion:deploy') -Value 'git push origin main'; deploy"; Operation = 'pushes to a git remote' }
        @{ Reason = 'writes to a drive name built with -join'; Command = "New-Item -Path (('func', 'tion:deploy') -join '') -Value 'git push origin main'; deploy"; Operation = 'pushes to a git remote' }
        @{ Reason = 'writes to a drive name built with -f'; Command = "New-Item -Path ('{0}{1}' -f 'func', 'tion:deploy') -Value 'git push origin main'; deploy"; Operation = 'pushes to a git remote' }
        @{ Reason = 'writes to a drive name held in a variable that was built with +'; Command = "`$d = 'func' + 'tion:deploy'; New-Item -Path `$d -Value 'git push origin main'; deploy"; Operation = 'pushes to a git remote' }
        @{ Reason = 'writes to a variable that was assigned twice, the second time a built name'; Command = "`$d = 'notes.txt'; `$d = 'func' + 'tion:deploy'; Set-Content -Path `$d -Value 'git push origin main'; deploy"; Operation = 'pushes to a git remote' }
        @{ Reason = 'writes to a variable that a loop binds'; Command = "foreach (`$d in ('func' + 'tion:deploy')) { Set-Content -Path `$d -Value 'git push origin main' }; deploy"; Operation = 'pushes to a git remote' }
        @{ Reason = 'writes to a variable that only a parameter binds'; Command = "param(`$d)`nSet-Content -Path `$d -Value 'git push origin main'"; Operation = 'pushes to a git remote' }
        @{ Reason = 'writes to a variable that -OutVariable replaces'; Command = "`$d = 'notes.txt'; Write-Output ('func' + 'tion:deploy') -OutVariable d; Set-Content -Path `$d -Value 'git push origin main'; deploy"; Operation = 'pushes to a git remote' }
        @{ Reason = 'writes to a variable that a reference changes'; Command = "`$d = 'notes.txt'; [void][uri]::TryCreate(('func' + 'tion:deploy'), 'Absolute', [ref]`$d); Set-Content -Path `$d -Value 'git push origin main'"; Operation = 'pushes to a git remote' }
        @{ Reason = 'writes a relative name after a built location change'; Command = "Set-Location ('func' + 'tion:'); Set-Content deploy 'git push origin main'; deploy"; Operation = 'pushes to a git remote' }
        @{ Reason = 'writes through a drive that was mapped to the Function provider'; Command = "New-PSDrive -Name x -PSProvider Function -Root '\'; Set-Content x:\deploy 'git push origin main'; deploy"; Operation = 'pushes to a git remote' }
        @{ Reason = 'pipes a literal into Set-Content with a built drive name'; Command = "'git push origin main' | Set-Content -Path ('func' + 'tion:deploy'); deploy"; Operation = 'pushes to a git remote' }
        @{ Reason = 'pipes Write-Output into Out-File with a built drive name'; Command = "Write-Output 'git push origin main' | Out-File -FilePath ('func' + 'tion:deploy'); deploy"; Operation = 'pushes to a git remote' }
        @{ Reason = 'names the Function drive in a provider-qualified path'; Command = "Set-Content -Path 'Microsoft.PowerShell.Core\Function::deploy' -Value 'git push origin main'; deploy"; Operation = 'pushes to a git remote' }
        @{ Reason = 'writes with New-Item to the Function drive and a name'; Command = "New-Item -Path function: -Name deploy -Value 'git push origin main'; deploy"; Operation = 'pushes to a git remote' }
        @{ Reason = 'gives Set-Content no path at all'; Command = "'git push origin main' | Set-Content"; Operation = 'pushes to a git remote' }
        @{ Reason = 'writes to a path that Join-Path computes'; Command = "`$p = Join-Path `$env:TEMP 'msg.txt'; Set-Content -LiteralPath `$p -Value 'docs: gh pr create'"; Operation = 'mutates a GitHub remote resource' }
        @{ Reason = 'writes to a path that starts with an environment variable'; Command = 'Set-Content -Path $env:TEMP\msg.txt -Value "docs: gh pr create"'; Operation = 'mutates a GitHub remote resource' }
        @{ Reason = 'writes the text of a variable to a computed path'; Command = "`$m = 'docs: git push'; Out-File -FilePath (Join-Path `$PWD 'm.txt') -InputObject `$m"; Operation = 'pushes to a git remote' }

        # Review of 2026-10-13, third pass, H1: PowerShell resolves parameter aliases and prefixes itself, so a
        # spelling the reader does not know can bind the path. An unknown parameter is not a known one.
        @{ Reason = 'names the path with the LP alias of -LiteralPath'; Command = "Set-Content -LP ('func' + 'tion:deploy') 'git push origin main'; deploy"; Operation = 'pushes to a git remote' }
        @{ Reason = 'names the path with the LP alias using Add-Content'; Command = "Add-Content -LP ('func' + 'tion:deploy') 'git push origin main'; deploy"; Operation = 'pushes to a git remote' }
        @{ Reason = 'names the path with the LP alias using Out-File'; Command = "Out-File -LP ('func' + 'tion:deploy') -InputObject 'git push origin main'; deploy"; Operation = 'pushes to a git remote' }
        @{ Reason = 'gives a writer a parameter that is not one of its parameters'; Command = "Set-Content -Bogus x -Path notes.txt -Value 'git push origin main'"; Operation = 'pushes to a git remote' }
        @{ Reason = 'gives a writer a parameter prefix that two parameters share'; Command = "Set-Content -V 'git push origin main' -Path notes.txt"; Operation = 'pushes to a git remote' }
        @{ Reason = 'splats an argument list into a writer'; Command = "`$a = @{ Path = ('func' + 'tion:deploy'); Value = 'git push origin main' }; Set-Content @a; deploy"; Operation = 'pushes to a git remote' }
        @{ Reason = 'splats a literal list into a writer'; Command = "`$a = 'notes.txt', 'git push origin main'; Set-Content @a"; Operation = 'pushes to a git remote' }

        # H2: a one-letter prefix of a parameter that stores output in a variable replaces a path variable.
        @{ Reason = 'replaces a path variable through -v of Tee-Object'; Command = "`$p = 'notes.txt'; ('func' + 'tion:deploy') | Tee-Object -v p; Set-Content -Path `$p -Value 'git push origin main'; deploy"; Operation = 'pushes to a git remote' }
        @{ Reason = 'replaces a path variable through a prefix of -OutVariable'; Command = "`$p = 'notes.txt'; Write-Output ('func' + 'tion:deploy') -o p; Set-Content -Path `$p -Value 'git push origin main'; deploy"; Operation = 'pushes to a git remote' }
        @{ Reason = 'replaces a path variable through a prefix of -PipelineVariable'; Command = "`$p = 'notes.txt'; ('func' + 'tion:deploy') | Write-Output -pi p; Set-Content -Path `$p -Value 'git push origin main'; deploy"; Operation = 'pushes to a git remote' }

        # H4 and the colon syntax: a relative path means whatever location the text, or an earlier call, left behind.
        @{ Reason = 'writes a relative name after popd'; Command = "popd; Set-Content -Path notes.ps1 -Value 'git push origin main'"; Operation = 'pushes to a git remote' }
        @{ Reason = 'writes a relative name after Pop-Location'; Command = "Pop-Location; Set-Content notes.ps1 'git push origin main'"; Operation = 'pushes to a git remote' }
        @{ Reason = 'writes a relative name after returning to the previous location'; Command = "cd -; Set-Content notes.ps1 'git push origin main'"; Operation = 'pushes to a git remote' }
        @{ Reason = 'writes a relative name after moving forward in the location history'; Command = "cd +; Set-Content notes.ps1 'git push origin main'"; Operation = 'pushes to a git remote' }
        @{ Reason = 'moves to a built location with the colon syntax of Set-Location'; Command = "Set-Location -Path:('func' + 'tion:'); Set-Content deploy 'git push origin main'; deploy"; Operation = 'pushes to a git remote' }
        @{ Reason = 'moves to a built location with the colon syntax of -LiteralPath'; Command = "Set-Location -LiteralPath:('func' + 'tion:'); Set-Content deploy 'git push origin main'; deploy"; Operation = 'pushes to a git remote' }
        @{ Reason = 'moves to a built location with the colon syntax of Push-Location'; Command = "Push-Location -Path:('func' + 'tion:'); Set-Content deploy 'git push origin main'; deploy"; Operation = 'pushes to a git remote' }
        @{ Reason = 'moves to a built location with the colon syntax of cd'; Command = "cd -Path:('func' + 'tion:'); Set-Content deploy 'git push origin main'; deploy"; Operation = 'pushes to a git remote' }

        # A common parameter that stores output in a variable carries the text out of an inert cmdlet, to wherever
        # the variable goes next. Found by the author's own probe after the third review pass.
        @{ Reason = 'captures Write-Output in a variable with -ov and hands it to wmic'; Command = "Write-Output 'git push origin main' -ov cmd > `$null; wmic process call create `$cmd"; Operation = 'pushes to a git remote' }
        @{ Reason = 'captures a warning with -WarningVariable and hands it to schtasks'; Command = "Write-Warning 'git push origin main' -WarningVariable w 3>`$null; schtasks /create /tn t /tr `$w"; Operation = 'pushes to a git remote' }
        @{ Reason = 'captures host text with -InformationVariable'; Command = "Write-Host 'git push origin main' -InformationVariable i 6>`$null; foo `$i"; Operation = 'pushes to a git remote' }
        @{ Reason = 'captures an error with -ErrorVariable'; Command = "Write-Error 'git push origin main' -ErrorVariable e 2>`$null; foo `$e"; Operation = 'pushes to a git remote' }
        @{ Reason = 'captures a write to a file with -PassThru and -OutVariable'; Command = "Set-Content -Path notes.txt -Value 'git push origin main' -PassThru -OutVariable cmd > `$null; foo `$cmd"; Operation = 'pushes to a git remote' }
        @{ Reason = 'binds the text to a pipeline variable with -pv'; Command = "Write-Output 'git push origin main' -pv p | Write-Output; foo `$p"; Operation = 'pushes to a git remote' }
        @{ Reason = 'pipes a literal into a cmdlet that stores it with -OutVariable'; Command = "'git push origin main' | Write-Output -OutVariable cmd > `$null; foo `$cmd"; Operation = 'pushes to a git remote' }
        @{ Reason = 'pipes a literal through a cmdlet that stores it into one that prints'; Command = "'git push origin main' | Write-Output -ov cmd | Write-Host; foo `$cmd"; Operation = 'pushes to a git remote' }

        # A file written into a folder that git or a hook runner executes holds code, not data.
        @{ Reason = 'writes a post-commit hook'; Command = "Set-Content -Path .git/hooks/post-commit -Value 'git push origin main'; git commit -m x"; Operation = 'pushes to a git remote' }
        @{ Reason = 'appends to a pre-push hook with a backslash path'; Command = "Add-Content -Path .\.git\hooks\pre-push -Value 'git push origin main'"; Operation = 'pushes to a git remote' }
        @{ Reason = 'writes a hook into a hooks path folder'; Command = "'git push origin main' | Set-Content .githooks/pre-commit"; Operation = 'pushes to a git remote' }
        @{ Reason = 'writes a husky hook'; Command = "Out-File -FilePath .husky/pre-commit -InputObject 'git push origin main'"; Operation = 'pushes to a git remote' }
        @{ Reason = 'writes the git config of a repository'; Command = "Set-Content -Path repo/.git/config -Value '[alias] p = !git push origin main'"; Operation = 'pushes to a git remote' }
        @{ Reason = 'writes a hook through a path variable'; Command = "`$h = '.git/hooks/post-commit'; Set-Content -Path `$h -Value 'git push origin main'"; Operation = 'pushes to a git remote' }

        # Review of 2026-10-13, fourth pass, I1: a profile, a shell start-up file, or a file in a Startup folder runs
        # by itself, in the agent's own next terminal, with no commit needed.
        @{ Reason = 'writes a PowerShell profile'; Command = "Set-Content -Path C:\Users\me\Documents\PowerShell\Microsoft.PowerShell_profile.ps1 -Value 'git push origin main'"; Operation = 'pushes to a git remote' }
        @{ Reason = 'appends to a profile.ps1'; Command = "Add-Content -Path profile.ps1 -Value 'git push origin main'"; Operation = 'pushes to a git remote' }
        @{ Reason = 'writes into a Windows Startup folder'; Command = "Set-Content -Path 'C:\Users\me\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\go.bat' -Value 'git push origin main'"; Operation = 'pushes to a git remote' }
        @{ Reason = 'writes a .bashrc'; Command = "Set-Content -Path /home/me/.bashrc -Value 'git push origin main'"; Operation = 'pushes to a git remote' }
        @{ Reason = 'appends to a .zshrc through a path variable'; Command = "`$f = '~/.zshrc'; Add-Content -Path `$f -Value 'git push origin main'"; Operation = 'pushes to a git remote' }
        @{ Reason = 'writes a .envrc that direnv runs'; Command = "Set-Content -Path .envrc -Value 'git push origin main'"; Operation = 'pushes to a git remote' }
        @{ Reason = 'writes a global git configuration'; Command = "Add-Content -Path ~/.gitconfig -Value '[alias] p = !git push origin main'"; Operation = 'pushes to a git remote' }
        @{ Reason = 'writes an ssh configuration'; Command = "Set-Content -Path ~/.ssh/config -Value 'ProxyCommand git push origin main'"; Operation = 'pushes to a git remote' }
        @{ Reason = 'writes a VS Code task file'; Command = "Set-Content -Path .vscode/tasks.json -Value 'git push origin main'"; Operation = 'pushes to a git remote' }
    )

    $script:parityCase = @(
        @{ Command = "Write-Output 'git push origin main'"; Blocked = $false }
        @{ Command = $evidenceTwo; Blocked = $false }
        @{ Command = 'git commit -m "docs: explain why gh pr create was denied"'; Blocked = $false }
        @{ Command = 'git push origin main'; Blocked = $true }
        @{ Command = 'git add . && git push'; Blocked = $true }
        @{ Command = "Invoke-Expression 'git push origin main'"; Blocked = $true }
        @{ Command = "Start-Process git -ArgumentList 'push origin main'"; Blocked = $true }
        @{ Command = "`$function:deploy = 'git push origin main'; deploy"; Blocked = $true }
        @{ Command = "`$x = 'git push origin main'; schtasks /create /tn t /tr `$x"; Blocked = $true }
        @{ Command = 'git --% push origin main'; Blocked = $true }
        @{ Command = "`$msg = 'docs: gh pr create'; git commit -m `$msg"; Blocked = $false }
        @{ Command = "New-Item -Path ('func' + 'tion:deploy') -Value 'git push origin main'; deploy"; Blocked = $true }
        @{ Command = "`$p = 'msg.txt'; Set-Content -LiteralPath `$p -Value 'docs: gh pr create'"; Blocked = $false }
        @{ Command = "Set-Content -LP ('func' + 'tion:deploy') 'git push origin main'; deploy"; Blocked = $true }
        @{ Command = "`$p = 'notes.txt'; ('func' + 'tion:deploy') | Tee-Object -v p; Set-Content -Path `$p -Value 'git push origin main'; deploy"; Blocked = $true }
        @{ Command = "Set-Location -Path:('func' + 'tion:'); Set-Content deploy 'git push origin main'; deploy"; Blocked = $true }
        @{ Command = "Set-Content -Lit notes.md -Value 'docs: git push' -Encoding utf8 -Force"; Blocked = $false }
        @{ Command = "Write-Output 'git push origin main' -ov cmd > `$null; wmic process call create `$cmd"; Blocked = $true }
    )

    # The engines whose cmdlets the parameter table is compared with.
    $engine = @(@{ Name = "PowerShell $($PSVersionTable.PSVersion.Major)"; Path = (Get-Process -Id $PID).Path })
    if ($script:windowsPowerShellAvailable) {
        $engine += @{ Name = 'Windows PowerShell 5.1'; Path = (Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe') }
    }

    $script:writerTableCase = foreach ($candidate in $engine) {
        foreach ($cmdlet in 'Set-Content', 'Add-Content', 'Out-File', 'New-Item') {
            @{ Engine = $candidate.Name; EnginePath = $candidate.Path; Cmdlet = $cmdlet }
        }
    }
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:guardScript = Join-Path -Path $script:repoRoot -ChildPath 'com.github.copilot/hooks/scripts/Block-RemoteMutation.ps1'
    $script:powerShellPath = (Get-Process -Id $PID).Path
    $script:windowsPowerShellPath = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
    }

    function script:Invoke-Guard {
        param(
            [Parameter(Mandatory)]
            [AllowEmptyString()]
            [string]$Payload,

            [Parameter()]
            [string]$PowerShellPath = $script:powerShellPath
        )

        $utf8 = [Text.UTF8Encoding]::new($false)
        $startInfo = [Diagnostics.ProcessStartInfo]::new($PowerShellPath)
        $startInfo.Arguments = '-NoProfile -NonInteractive -File "{0}"' -f $script:guardScript
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.StandardOutputEncoding = $utf8
        $startInfo.StandardErrorEncoding = $utf8
        $startInfo.EnvironmentVariables.Remove('COPILOT_ATELIER_ALLOW_REMOTE')

        $process = [Diagnostics.Process]::Start($startInfo)
        try {
            $outputTask = $process.StandardOutput.ReadToEndAsync()
            $errorTask = $process.StandardError.ReadToEndAsync()
            $bytes = $utf8.GetBytes($Payload)
            $process.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
            $process.StandardInput.Close()
            if (-not $process.WaitForExit(60000)) {
                $process.Kill()
                throw 'Block-RemoteMutation.ps1 did not exit within 60 seconds.'
            }

            $process.WaitForExit()
            [pscustomobject]@{
                ExitCode = $process.ExitCode
                StdOut = $outputTask.Result
                StdErr = $errorTask.Result
                Output = "$($outputTask.Result)$($errorTask.Result)"
            }
        } finally {
            $process.Dispose()
        }
    }

    function script:New-CommandPayload {
        param(
            [Parameter(Mandatory)]
            [string]$Command
        )

        [ordered]@{
            hook_event_name = 'PreToolUse'
            session_id = 'literal-tests'
            tool_name = 'run_in_terminal'
            tool_input = [ordered]@{ command = $Command }
        } | ConvertTo-Json -Depth 5 -Compress
    }
}

Describe 'Block-RemoteMutation string literals' -Tag 'Unit' {
    It 'allows a command that only mentions a remote mutation: <Reason>' -ForEach $script:allowedCase {
        $result = script:Invoke-Guard -Payload (script:New-CommandPayload -Command $Command)

        $result.ExitCode | Should -Be 0 -Because $result.Output
        $result.StdOut | Should -BeNullOrEmpty -Because 'an allowed call must print no decision: a hook allow would approve the call in VS Code'
    }

    It 'still blocks a command that invokes a blocked operation: <Reason>' -ForEach $script:blockedCase {
        $result = script:Invoke-Guard -Payload (script:New-CommandPayload -Command $Command)

        $result.ExitCode | Should -Be 2 -Because $result.Output
        $result.Output | Should -Match ([regex]::Escape("Blocked by Copilot Atelier: this command $Operation"))
    }

    It 'treats a mention in a field that is not a command as before' {
        $payload = [ordered]@{
            hook_event_name = 'PreToolUse'
            session_id = 'literal-tests'
            tool_name = 'run_task'
            tool_input = [ordered]@{ command = 'echo'; args = @('git push origin main') }
        } | ConvertTo-Json -Depth 5 -Compress

        $result = script:Invoke-Guard -Payload $payload

        $result.ExitCode | Should -Be 2 -Because 'an argument array is not source text, so it stays scanned'
    }

    It 'does not let a masked literal hide a push placed on the next line' {
        $command = @("Write-Output 'text'", 'git push origin main') -join "`n"

        $result = script:Invoke-Guard -Payload (script:New-CommandPayload -Command $command)

        $result.ExitCode | Should -Be 2 -Because $result.Output
    }

    It 'allows launching a program that is not git or gh' {
        $result = script:Invoke-Guard -Payload (script:New-CommandPayload -Command "Start-Process notepad -ArgumentList 'notes.txt'")

        $result.ExitCode | Should -Be 0 -Because $result.Output
    }

    It 'allows launching git with an argument list that holds nothing blocked' {
        $result = script:Invoke-Guard -Payload (script:New-CommandPayload -Command "Start-Process git -ArgumentList 'status','--short' -Wait")

        $result.ExitCode | Should -Be 0 -Because $result.Output
    }
}

Describe 'Block-RemoteMutation string literals under Windows PowerShell' -Tag 'Unit' -Skip:(-not $script:windowsPowerShellAvailable) {
    <#
        VS Code runs the guard with Windows PowerShell 5.1, whose parser does not
        know && and || and rejects the text. Text that does not parse is scanned
        as it always was, so the same cases hold there.
    #>
    It 'decides the same way in Windows PowerShell for: <Command>' -ForEach $script:parityCase {
        $result = script:Invoke-Guard -Payload (script:New-CommandPayload -Command $Command) -PowerShellPath $script:windowsPowerShellPath

        $result.ExitCode | Should -Be $(if ($Blocked) { 2 } else { 0 }) -Because $result.Output
    }
}

Describe 'Block-RemoteMutation file-writer parameter table' -Tag 'Unit' {
    <#
        PowerShell binds a parameter by name, by alias, or by an unambiguous prefix of either, so the guard
        reads the parameters of the four file writers from a closed table. A name that is missing from it
        makes the target unreadable, which blocks; a name that is listed with the wrong kind lets a path
        pass as a value (review of 2026-10-13, third pass, H1: -LP is an alias, not a prefix). This
        compares the table with the cmdlets of every engine that is installed.
    #>
    BeforeAll {
        $script:metadataScript = @'
$rows = foreach ($name in 'Set-Content', 'Add-Content', 'Out-File', 'New-Item') {
    foreach ($parameter in (Get-Command -Name $name -CommandType Cmdlet).Parameters.Values) {
        [pscustomobject]@{ Cmdlet = $name; Name = $parameter.Name; Alias = @($parameter.Aliases); IsSwitch = ($parameter.ParameterType -eq [switch]) }
    }
}

ConvertTo-Json -InputObject @($rows) -Compress -Depth 4
'@

        $script:contentParameter = @{ 'Set-Content' = '-Value'; 'Add-Content' = '-Value'; 'Out-File' = '-InputObject'; 'New-Item' = '-Value' }
        $script:pathName = @('Path', 'LiteralPath', 'PSPath', 'LP', 'FilePath', 'Name')

        # A parameter that stores the output in a variable makes the writer carry the text on, so the guard
        # does not treat that command as inert whatever the table says; the capture cases cover those.
        $script:variableStoringName = @('OutVariable', 'ov', 'ErrorVariable', 'ev', 'WarningVariable', 'wv', 'InformationVariable', 'iv', 'PipelineVariable', 'pv')

        function script:Get-WriterParameter {
            param(
                [Parameter(Mandatory)]
                [string]$PowerShellPath,

                [Parameter(Mandatory)]
                [string]$Cmdlet
            )

            $json = & $PowerShellPath -NoProfile -NonInteractive -Command $script:metadataScript
            @($json | ConvertFrom-Json) | Where-Object -FilterScript { $_.Cmdlet -eq $Cmdlet }
        }

        function script:New-WriterStatement {
            param(
                [Parameter(Mandatory)]
                [string]$Cmdlet,

                [Parameter(Mandatory)]
                [string]$Name,

                [Parameter(Mandatory)]
                [bool]$IsSwitch,

                [Parameter()]
                [string]$Argument = 'x'
            )

            $statement = "$Cmdlet -Path 'n.txt' $($script:contentParameter[$Cmdlet]) 'docs: git push' -$Name"
            if (-not $IsSwitch) {
                $statement += " $Argument"
            }

            $statement
        }
    }

    It 'knows every parameter and alias of <Cmdlet> in <Engine>' -ForEach $script:writerTableCase {
        $row = script:Get-WriterParameter -PowerShellPath $EnginePath -Cmdlet $Cmdlet
        $row.Count | Should -BeGreaterThan 10 -Because 'the metadata of the cmdlet could not be read'

        $statement = foreach ($parameter in $row) {
            foreach ($name in @($parameter.Name) + @($parameter.Alias)) {
                if ($script:variableStoringName -contains $name) {
                    continue
                }

                script:New-WriterStatement -Cmdlet $Cmdlet -Name $name -IsSwitch ([bool]$parameter.IsSwitch)
            }
        }

        $result = script:Invoke-Guard -Payload (script:New-CommandPayload -Command ($statement -join '; '))
        $unknown = @()
        if ($result.ExitCode -ne 0) {
            foreach ($line in $statement) {
                $single = script:Invoke-Guard -Payload (script:New-CommandPayload -Command $line)
                if ($single.ExitCode -ne 0) {
                    $unknown += $line
                }
            }
        }

        $result.ExitCode | Should -Be 0 -Because "the table of Block-RemoteMutation.ps1 lacks a parameter or alias of ${Cmdlet}; the statements that were blocked: $($unknown -join ' | ')"
    }

    It 'treats every path parameter of <Cmdlet> in <Engine> as the file it writes' -ForEach $script:writerTableCase {
        $row = script:Get-WriterParameter -PowerShellPath $EnginePath -Cmdlet $Cmdlet
        $misread = @()
        foreach ($parameter in $row) {
            foreach ($name in @($parameter.Name) + @($parameter.Alias)) {
                if ($script:pathName -cnotcontains $name) {
                    continue
                }

                # The path is built, so only a parameter that the guard reads as the path blocks it.
                $statement = script:New-WriterStatement -Cmdlet $Cmdlet -Name $name -IsSwitch $false -Argument "('func' + 'tion:deploy')"
                $result = script:Invoke-Guard -Payload (script:New-CommandPayload -Command $statement)
                if ($result.ExitCode -ne 2) {
                    $misread += $name
                }
            }
        }

        $misread | Should -BeNullOrEmpty -Because "a parameter that names the file of $Cmdlet is read as something else: $($misread -join ', ')"
    }
}
