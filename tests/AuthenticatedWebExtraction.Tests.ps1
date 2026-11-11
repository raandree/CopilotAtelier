BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:skillRoot = Join-Path $script:repoRoot 'skills/authenticated-web-extraction'
    $script:bootstrapRoot = Join-Path $script:skillRoot 'bootstrap'
    $script:nodeTestPath = @(
        Join-Path $PSScriptRoot 'AuthenticatedWebExtraction/reddit-url.test.mjs'
        Join-Path $PSScriptRoot 'AuthenticatedWebExtraction/reddit-read.test.mjs'
        Join-Path $PSScriptRoot 'AuthenticatedWebExtraction/dump-cookies.test.mjs'
    )
    $script:skillText = Get-Content -LiteralPath (Join-Path $script:skillRoot 'SKILL.md') -Raw
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

Describe 'authenticated-web-extraction bootstrap recipe' -Tag 'Unit' {
    It 'copies every bundled file to a fresh machine' {
        $bundled = Get-ChildItem -LiteralPath $script:bootstrapRoot -Recurse -File |
            ForEach-Object -Process { $_.FullName.Substring($script:bootstrapRoot.Length + 1) -replace '/', '\' }

        foreach ($relativePath in $bundled)
        {
            $script:skillText | Should -Match ([regex]::Escape('"$src\' + $relativePath + '"')) -Because "the recipe must copy $relativePath"
        }
    }
}
