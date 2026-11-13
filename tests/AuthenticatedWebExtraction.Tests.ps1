BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:skillRoot = Join-Path $script:repoRoot 'skills/authenticated-web-extraction'
    $script:bootstrapRoot = Join-Path $script:skillRoot 'bootstrap'
    $script:nodeTestPath = @(
        Join-Path $PSScriptRoot 'AuthenticatedWebExtraction/reddit-url.test.mjs'
        Join-Path $PSScriptRoot 'AuthenticatedWebExtraction/reddit-read.test.mjs'
        Join-Path $PSScriptRoot 'AuthenticatedWebExtraction/dump-cookies.test.mjs'
    )
    $script:skillText = Get-Content -LiteralPath (Join-Path $script:skillRoot 'SKILL.md') -Raw -Encoding UTF8
    $script:agentsRoot = Join-Path $script:repoRoot 'com.github.copilot/agents'
    $script:readerText = Get-Content -LiteralPath (Join-Path $script:agentsRoot 'quarantined-reader.agent.md') -Raw -Encoding UTF8
    $script:readerFrontmatter = [regex]::Match($script:readerText, '\A---\r?\n(?<head>.*?)\r?\n---', 'Singleline').Groups['head'].Value
    $agentsReadme = Get-Content -LiteralPath (Join-Path $script:agentsRoot 'README.md') -Raw -Encoding UTF8
    $script:readerReadme = [regex]::Match($agentsReadme, '(?ms)^### \d+\. Quarantined Reader Agent\r?$.*?(?=^---\r?$)').Value
    $script:redditSection = [regex]::Match($script:skillText, '(?ms)^## Signed-in Reddit Reading\r?$.*?(?=^## )').Value

    # The entries of the quarantine since 6.1.0; the released 6.1.0 entries keep their history.
    $changelog = Get-Content -LiteralPath (Join-Path $script:repoRoot 'CHANGELOG.md') -Raw -Encoding UTF8
    $script:changelogEntry = @(
        ($changelog -split '(?m)^## \[6\.1\.0\]')[0] -split '\r?\n' |
            Where-Object -FilterScript { $_ -match '^- ' -and $_ -match 'quarantined-reader' }
    ) -join "`n"

    function Get-NormalizedSha256
    {
        <#
            The SHA-256 of a text with LF line endings and no blank lines at
            either end, so that a checkout with CRLF line endings pins the same
            value as one with LF.
        #>
        param (
            [Parameter(Mandatory)]
            [AllowEmptyString()]
            [string] $Text
        )

        $normalized = (($Text -split '\r?\n') -join "`n").Trim()
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try
        {
            ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($normalized))) -replace '-', '').ToLowerInvariant()
        }
        finally
        {
            $sha.Dispose()
        }
    }

    function Get-Clause
    {
        <#
            Splits Markdown into clauses: every line, cut again after a full
            stop, semicolon, colon, question mark, or exclamation mark that a
            blank follows, so that a negation in one clause cannot excuse the
            next.
        #>
        param (
            [Parameter(Mandatory)]
            [AllowEmptyString()]
            [string] $Text
        )

        foreach ($line in $Text -split '\r?\n')
        {
            foreach ($clause in $line -split '(?<=[.;:?!])\s+')
            {
                if ($clause.Trim())
                {
                    $clause.Trim()
                }
            }
        }
    }
}

Describe 'authenticated-web-extraction signed-in Reddit reading' -Tag 'Unit' {
    It 'checks the Reddit sign-in by the reddit_session cookie' {
        $text = Get-Content -LiteralPath (Join-Path $script:bootstrapRoot 'tasks/check-logins.mjs') -Raw

        $text | Should -Match "cookieDomain:\s*'https://www\.reddit\.com'"
        $text | Should -Match "cookieName:\s*'reddit_session'"
    }

    It 'passes the Node tests of the Reddit task and the cookie dump' {
        # The allow-list is the containment control: text read through the
        # signed-in session must never choose the next address it fetches.
        $nodeCommand = Get-Command -Name node -CommandType Application -ErrorAction SilentlyContinue
        if (-not $nodeCommand) {
            # Skipping in CI would report a green build with no tests behind
            # the allow-list.
            if ($env:CI -eq 'true') {
                throw 'node is not on PATH, so the Reddit allow-list tests cannot run.'
            }

            Set-ItResult -Skipped -Because 'node is not installed, so the Reddit task tests cannot run'
            return
        }

        $output = & $nodeCommand --test --test-reporter tap $script:nodeTestPath 2>&1 |
            ForEach-Object -Process { [string]$_ }

        $LASTEXITCODE | Should -Be 0 -Because ($output -join [System.Environment]::NewLine)
    }

    It 'keeps the Reddit session cookie out of the plaintext auth-state copy' {
        $openText = Get-Content -LiteralPath (Join-Path $script:bootstrapRoot 'scripts/open.mjs') -Raw
        $tracked = [regex]::Match($openText, 'const trackedDomains = \[([^\]]*)\]')

        $tracked.Success | Should -BeTrue -Because 'open.mjs lists the domains whose cookies it copies to auth-state'
        $tracked.Groups[1].Value | Should -Not -Match 'reddit' -Because 'auth-state keeps a plaintext copy of every tracked cookie, and the Reddit cookie stays in the profile only'
        $script:skillText | Should -Not -Match 'Add `https://www\.reddit\.com` to `trackedDomains`'
    }

    It 'reads Reddit results only through a reader that can read files and nothing else' {
        $agentPath = Join-Path $script:repoRoot 'com.github.copilot/agents/quarantined-reader.agent.md'
        $agentText = Get-Content -LiteralPath $agentPath -Raw
        $tools = [regex]::Match($agentText, '(?m)^tools:\s*\[(.*)\]\r?$').Groups[1].Value

        $tools | Should -BeExactly "'read/readFile'" -Because 'any other tool would give text injected into a Reddit thread a channel out'
        $script:skillText | Should -Match '`quarantined-reader`'
        $script:skillText | Should -Match 'Never open `extracted/reddit/`'
    }

    It 'fetches through the allow-list and never from a URL in its arguments' {
        $text = Get-Content -LiteralPath (Join-Path $script:bootstrapRoot 'tasks/reddit-read.mjs') -Raw

        $text | Should -Match "from '\.\./lib/reddit-url\.mjs'"
        $text | Should -Match 'buildRedditUrl\('
        $text | Should -Not -Match 'page\.goto\(\s*(args|request|r)\b' -Because 'a navigation target must not come from input'
    }
}

Describe 'authenticated-web-extraction keeps Reddit text away from every agent that can act' -Tag 'Unit' {
    It 'scopes every read or copy of task output away from reddit-read' {
        # RR03-01: "Read its output from extracted/" with no exception sent the
        # agent that holds the shell into extracted/reddit/ as well.
        $generic = '(?i)\b(its|the|their|this) output\b(?!\W+of\s+`)|`extracted/`'
        $access = '(?i)\b(read|reads|open|opens|view|views|copy|copies|load|loads|transform|transforms)\b'
        $scoped = '(?i)\b(except|never|not|other than|apart from)\b.{0,80}\breddit|\breddit.{0,80}\b(except|never|not)\b'

        $unscoped = @(
            Get-Clause -Text ($script:skillText -replace '\\', '/') |
                Where-Object -FilterScript { $_ -match $generic -and $_ -match $access -and $_ -notmatch $scoped }
        )

        $unscoped | Should -BeNullOrEmpty -Because 'a step that reads or copies task output must leave out reddit-read, whose output no agent that can act reads'
    }

    It 'never sends an agent into extracted/reddit/' {
        # Probe M1d of the re-review of #53: a Skill that told the caller to
        # open extracted/reddit/ itself passed every test.
        $access = '\b(read|reads|reading|open|opens|opening|view|views|copy|copies|copying|load|loads|cat|grep|ls|dir|gci|gc|Get-Content|Get-ChildItem|Select-String|sls)\b'

        $directed = @(
            Get-Clause -Text ($script:skillText -replace '\\', '/') |
                Where-Object -FilterScript {
                    $prose = $_ -replace '`[^`]*`', '``'
                    $_ -match '(?i)extracted/reddit' -and
                    $prose -match "(?i)$access" -and
                    $prose -notmatch "(?i)(\b(never|not|no|nor)\b|n't\b|\bthe user\b).*$access"
                }
        )

        $directed | Should -BeNullOrEmpty -Because 'only a clause that forbids it, or that names the user as the reader, may pair extracted/reddit/ with a way to read it'
    }

    It 'leaves the check against the raw files to the user' {
        # RR03-01: "check a decision against the raw files" made the agent that
        # holds the shell the reader of the raw Reddit text.
        $check = '\b(check|checks|checked|checking|verify|verifies|compare|compares|confirm|confirms)\b'
        $texts = [ordered] @{
            'SKILL.md'                       = $script:skillText
            'quarantined-reader.agent.md'    = $script:readerText
            'the reader''s README section'   = $script:readerReadme
        }

        $script:readerReadme | Should -Not -BeNullOrEmpty -Because 'the agents README documents the reader in a section of its own'
        foreach ($entry in $texts.GetEnumerator())
        {
            $agentCheck = @(
                Get-Clause -Text $entry.Value |
                    Where-Object -FilterScript {
                        $_ -match '(?i)\braw\b' -and $_ -match "(?i)$check" -and $_ -notmatch "(?i)\bthe user\b.*$check"
                    }
            )

            $agentCheck | Should -BeNullOrEmpty -Because "$($entry.Key) must leave the check against the raw Reddit text to the user"
        }
    }

    It 'makes no containment claim that the reader does not meet' {
        # RR03-02: the reader can read the plaintext cookies in auth-state/,
        # and nothing deterministic checks what its summary carries.
        $claims = @(
            '(?i)\bno (channel|way) out\b'
            '(?i)\bbreak(s|ing)?\s+the\s+lethal\s+trifecta\b'
            '(?i)\bnever (reaches|sees)\b'
        )
        $texts = [ordered] @{
            'SKILL.md'                       = $script:skillText
            'quarantined-reader.agent.md'    = $script:readerText
            'the reader''s README section'   = $script:readerReadme
            'the CHANGELOG entry'            = $script:changelogEntry
        }

        $script:readerReadme | Should -Not -BeNullOrEmpty -Because 'the agents README documents the reader in a section of its own'
        $script:changelogEntry | Should -Not -BeNullOrEmpty -Because 'the CHANGELOG records the quarantine since 6.1.0'
        foreach ($entry in $texts.GetEnumerator())
        {
            foreach ($claim in $claims)
            {
                $entry.Value | Should -Not -Match $claim -Because "$($entry.Key) must not claim more than the quarantine delivers"
            }
        }
    }

    It 'names the call by name that VS Code still allows' {
        # R16-01: in VS Code 1.146.0 local chat, disable-model-invocation only
        # hides the reader from the subagent list; runSubagent still runs it by
        # name for a caller without an explicit agents: list.
        $script:redditSection | Should -Match '(?i)\bthe user asks\b[^.]*`quarantined-reader`[^.]*\bdecline' -Because 'an agent must not run the reader even when the user asks'
        $script:readerText | Should -Not -Match '(?i)\bthe user started you\b' -Because 'a host can still run the reader as a subagent by name'
        $texts = [ordered] @{
            'SKILL.md, Signed-in Reddit Reading' = $script:redditSection
            'the reader''s README section'       = $script:readerReadme
            'the CHANGELOG entry'                = $script:changelogEntry
        }

        foreach ($entry in $texts.GetEnumerator())
        {
            $entry.Value | Should -Match '(?i)\bbuilt-in Agent\b' -Because "$($entry.Key) must name the caller that VS Code still lets run the reader by name"
            $entry.Value | Should -Match '(?i)`infer: false`' -Because "$($entry.Key) must say what the agent host makes of the flag"
            $entry.Value | Should -Match '(?i)\bhook\b' -Because "$($entry.Key) must name the deterministic close that is still open"
        }
    }

    It 'keeps every agent that can run subagents from reaching the reader by name' {
        # R16-02: VS Code refuses a call by name only through the caller's own
        # agents: list, and infer: wins over disable-model-invocation.
        $script:readerFrontmatter | Should -Not -Match '(?m)^infer\s*:' -Because 'VS Code and its agent host let infer win over disable-model-invocation'

        foreach ($agentFile in Get-ChildItem -LiteralPath $script:agentsRoot -Filter '*.agent.md' -File)
        {
            $head = [regex]::Match((Get-Content -LiteralPath $agentFile.FullName -Raw -Encoding UTF8), '\A---\r?\n(?<head>.*?)\r?\n---', 'Singleline').Groups['head'].Value
            $toolsMatch = [regex]::Match($head, '(?m)^tools:\s*\[(?<list>.*)\]\s*$')
            $tools = @([regex]::Matches($toolsMatch.Groups['list'].Value, '''([^'']+)''') | ForEach-Object -Process { $_.Groups[1].Value })
            if ($toolsMatch.Success -and -not ($tools -match '^agent(/|$)'))
            {
                continue
            }

            $agentsMatch = [regex]::Match($head, '(?m)^agents:(?<value>[^\r\n]*(?:\r?\n[ \t]+-[^\r\n]*)*)')
            $agentsMatch.Success | Should -BeTrue -Because "$($agentFile.Name) can run subagents, and only its own agents: list stops VS Code from running the reader by name"
            $value = $agentsMatch.Groups['value'].Value
            $value | Should -Match '^\s*\[[^\]]*\]\s*$|\r?\n[ \t]+-' -Because "$($agentFile.Name) must list the agents it may run"
            $value | Should -Not -Match '\*' -Because "$($agentFile.Name) must not let VS Code run any agent by name"
            $value | Should -Not -Match 'quarantined-reader' -Because "$($agentFile.Name) must not run the reader"
        }
    }

    It 'pins the reviewed text of the Reddit quarantine' {
        # R16-04: word lists let a reworded instruction through, so the text a
        # reviewer approved is pinned whole. Re-pin a value only after an
        # independent review of the new text; the tests above give the reasons
        # it has to hold.
        $workflow = [regex]::Match($script:skillText, '(?ms)^## Standard Workflow\r?$(?<body>.*?)(?=^## )').Groups['body'].Value
        $pinned = [ordered] @{
            'SKILL.md, Standard Workflow steps 3 and 4' = @{
                Text   = [regex]::Match($workflow, '(?ms)^3\. .*').Value
                Sha256 = '6b6c4a86e93736b30cac75bd3e2149c2a94a4d905eedff4db6a07aa7faaa2b4c'
            }
            'SKILL.md, Signed-in Reddit Reading'        = @{
                Text   = $script:redditSection
                Sha256 = '3031b9c9fdc40f22ee049cfef643d6a613cdee7a4fb35f6dc8de1b2918279105'
            }
            'the reader''s README section'              = @{
                Text   = $script:readerReadme
                Sha256 = '8cdc11cf22a3d4e888bc8c5ae9ab35290dff57344bf6365c6e177af1048cbba5'
            }
        }

        foreach ($entry in $pinned.GetEnumerator())
        {
            $entry.Value.Text | Should -Not -BeNullOrEmpty -Because "$($entry.Key) must exist to be pinned"
            Get-NormalizedSha256 -Text $entry.Value.Text |
                Should -Be $entry.Value.Sha256 -Because "$($entry.Key) changed after its review; re-pin it only after an independent review of the new text"
        }
    }

    It 'asks the user to retire the companion prompt for Reddit' {
        # R16-05: the user-level prompt still sends an agent to every task's
        # output, and an agent that follows it has no reason to load this Skill.
        $companion = [regex]::Match($script:skillText, '(?ms)^## Companion Prompt\r?$(?<body>.*?)(?=^## |\z)').Groups['body'].Value

        $companion | Should -Match '(?i)\bthe user\b[^.]*\bdelete\b' -Because 'only the user can change a prompt in their own profile'
        $companion | Should -Match '(?i)\bkeep `reddit-read` out\b'
        $script:redditSection | Should -Match 'auth-extract\.prompt\.md' -Because 'the remaining limits must name the prompt'
        $script:changelogEntry | Should -Match 'auth-extract\.prompt\.md' -Because 'the upgrade note must name the prompt'
    }

    It 'leaves the summary of the quarantined reader to the user' {
        # Option 1 of brief 16: the user starts the reader in a new chat, so no
        # agent that can act starts it or receives its summary.
        $script:readerFrontmatter | Should -Match '(?m)^user-invocable:\s*true\s*$' -Because 'the user starts the reader from the agent picker'
        $script:readerFrontmatter | Should -Match '(?m)^disable-model-invocation:\s*true\s*$' -Because 'the flag hides the reader from the subagent list in VS Code and makes the Copilot CLI refuse it by name'
        $script:readerText | Should -Not -Match '(?i)\bcall(er|ers|ing agent)\b' -Because 'the reader answers the user, not an agent that called it'

        $namingAgent = @(
            Get-ChildItem -LiteralPath $script:agentsRoot -Filter '*.agent.md' -File |
                Where-Object -FilterScript {
                    $head = [regex]::Match((Get-Content -LiteralPath $_.FullName -Raw), '\A---\r?\n(?<head>.*?)\r?\n---', 'Singleline').Groups['head'].Value
                    $_.Name -ne 'quarantined-reader.agent.md' -and $head -match 'quarantined-reader'
                } |
                ForEach-Object -Process { $_.Name }
        )
        $namingAgent | Should -BeNullOrEmpty -Because 'naming the reader under agents overrides disable-model-invocation, and a handoff moves its summary into that agent''s chat'

        $verb = '(dispatch|dispatches|delegate|delegates|invoke|invokes|treat|treats|read|reads|check|checks|receive|receives|use|uses|relay|relays|accept|accepts|discard|discards|paste|pastes|act on|acts on|ask for|asks for)'
        $directive = "(?i)^\W*((then|first|next|now|also|afterwards|finally|and|or|so)\W+)*$verb\b|\b(you|callers?|(the|this|that|calling|acting|your) agent)\b[^.;:]{0,40}\b$verb\b"
        $negated = "(?i)(\b(never|not|no|nor)\b|n't\b).*\b$verb\b"
        $directed = @(
            Get-Clause -Text $script:skillText |
                Where-Object -FilterScript {
                    $_ -match '(?i)quarantined[- ]reader|\bthe reader\b|\bsummar(y|ies)\b' -and
                    $_ -match $directive -and
                    $_ -notmatch $negated
                }
        )
        $directed | Should -BeNullOrEmpty -Because 'no text an agent follows may tell it to start the reader or to read, check, or act on its summary'
    }

    It 'exempts the quarantined reader from the reads of the shared lifecycle' {
        # RR03-03: pre-flight "as far as reading allows" loaded the Memory Bank
        # and Skills into the context where Reddit text is read.
        $lifecycle = [regex]::Match($script:readerText, '(?ms)^## Shared lifecycle\r?$(?<body>.*?)(?=^## )').Groups['body'].Value

        $lifecycle | Should -Match '\(\.\./rules/preflight\.instructions\.md\)'
        $lifecycle | Should -Match '\(\.\./rules/postflight\.instructions\.md\)'
        $lifecycle | Should -Not -Match '(?i)as far as' -Because 'a partial pre-flight still reads the Memory Bank and Skills'

        # R16-07: a negation only counts right next to the item it negates, and
        # an exception can reverse the exemption within its own sentence.
        $lifecycle | Should -Not -Match '(?i)\bexcept\b' -Because 'an exception can reverse the exemption'
        foreach ($exempted in 'Memory Bank', 'Skill', 'Instruction')
        {
            $lifecycle | Should -Match "(?i)\bno\s+$exempted" -Because "the reader reads no $exempted"
        }

        $lifecycle | Should -Match '(?i)\bno\b[^.,;]*\bbanner\b' -Because 'the reader writes no banner'
        $lifecycle | Should -Match '(?i)only the files the user names'

        # R16-03: the session-start hook adds its own note to every chat, and
        # that note calls its Memory Bank probe authoritative.
        $lifecycle | Should -Match '(?i)\bsession-start hook\b' -Because 'the exemption must name the hook''s note as well'
        $lifecycle | Should -Match '(?i)\bignore\b[^.]*\bMemory Bank line\b[^.]*\bPRE-FLIGHT\b[^.]*\bclosing command\b' -Because 'the reader must ignore each line of that note that asks for a read, a banner, or a command'
        $script:readerReadme | Should -Match '(?i)\bis told to read no\b' -Because 'the exemption is an instruction, not a host control'
        $script:changelogEntry | Should -Match '(?i)\bis told to read no\b' -Because 'the exemption is an instruction, not a host control'
        foreach ($text in $script:redditSection, $script:readerReadme, $script:changelogEntry)
        {
            $text | Should -Match '(?i)\bsession-start hook\b' -Because 'the remaining limits must name the lifecycle the hosts still put into the reader''s chat'
        }
    }
}

Describe 'authenticated-web-extraction bootstrap recipe' -Tag 'Unit' {
    It 'names every file an installation from before Reddit reading needs' {
        # R16-08: an extract.mjs from before Reddit reading passes no headless
        # flag, so reddit-read refuses every run until it is copied in too.
        $upgrade = [regex]::Match($script:skillText, '(?m)^An installation that predates Reddit reading[^\r\n]*').Value

        $upgrade | Should -Not -BeNullOrEmpty
        foreach ($file in 'scripts\extract.mjs', 'tasks\check-logins.mjs', 'tasks\reddit-read.mjs', 'lib\reddit-url.mjs')
        {
            $upgrade | Should -Match ([regex]::Escape($file)) -Because "reddit-read needs $file"
        }
    }

    It 'copies every bundled file to a fresh machine' {
        $bundled = Get-ChildItem -LiteralPath $script:bootstrapRoot -Recurse -File |
            ForEach-Object -Process { $_.FullName.Substring($script:bootstrapRoot.Length + 1) -replace '/', '\' }

        foreach ($relativePath in $bundled)
        {
            $script:skillText | Should -Match ([regex]::Escape('"$src\' + $relativePath + '"')) -Because "the recipe must copy $relativePath"
        }
    }
}
