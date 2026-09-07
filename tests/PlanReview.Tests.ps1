$script:repoRoot = Split-Path -Parent $PSScriptRoot

BeforeDiscovery {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:planReviewRoot = Join-Path $script:repoRoot 'tools/plan-review'

    <#
        The dependency-free half of the Node suite is discovered here so each
        file becomes its own It. The rest of the package needs `npm install`
        under tools/plan-review and stays out of the repository gate.
    #>
    $script:nodeAvailable = [bool](Get-Command -Name node -CommandType Application -ErrorAction SilentlyContinue)

    $script:nodeUnitCase = @(
        Get-ChildItem -Path (Join-Path $script:planReviewRoot 'test/unit') -Filter '*.test.mjs' -File -ErrorAction SilentlyContinue |
            ForEach-Object -Process {
                @{
                    Name = $_.Name
                    RelativePath = "test/unit/$($_.Name)"
                }
            }
    )
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:planReviewRoot = Join-Path $script:repoRoot 'tools/plan-review'
    $script:sourceRoot = Join-Path $script:planReviewRoot 'src'
    $script:assetRoot = Join-Path $script:planReviewRoot 'assets'
    $script:nodeAvailable = [bool](Get-Command -Name node -CommandType Application -ErrorAction SilentlyContinue)

    $script:serverText = Get-Content -LiteralPath (Join-Path $script:sourceRoot 'server.mjs') -Raw
    $script:storeText = Get-Content -LiteralPath (Join-Path $script:sourceRoot 'store.mjs') -Raw
    $script:renderText = Get-Content -LiteralPath (Join-Path $script:sourceRoot 'render.mjs') -Raw

    $script:packageText = @(
        Get-ChildItem -LiteralPath $script:sourceRoot -Filter '*.mjs' -File
        Get-ChildItem -LiteralPath $script:assetRoot -File
    ) | ForEach-Object -Process {
        [pscustomobject]@{
            Name = $_.Name
            Text = Get-Content -LiteralPath $_.FullName -Raw
        }
    }
}

Describe 'Plan review package layout' -Tag 'Unit' {
    It 'Should ship the optional package outside the module payload' {
        <#
            build.yaml lists what Copy_Customizations_To_Output copies into the
            built module. The review surface is opt-in, so a Gallery install
            must not carry it or its Node dependencies.
        #>
        $buildConfiguration = Get-Content -LiteralPath (Join-Path $script:repoRoot 'build.yaml') -Raw

        $buildConfiguration | Should -Not -Match '(?m)^\s*-\s*tools'
    }

    It 'Should keep the PowerShell module free of any dependency on it' {
        $reference = @(
            Get-ChildItem -Path (Join-Path $script:repoRoot 'source') -Recurse -File -Filter '*.ps1' |
                Where-Object -FilterScript {
                    (Get-Content -LiteralPath $_.FullName -Raw) -match 'plan-review|plan_review'
                }
        )

        $reference | Should -BeNullOrEmpty -Because 'ordinary module consumers must stay PowerShell-native'
    }

    It 'Should ignore the installed Node dependencies and browser artifacts' {
        $ignore = Get-Content -LiteralPath (Join-Path $script:repoRoot '.gitignore') -Raw

        $ignore | Should -Match 'tools/plan-review/node_modules'
        $ignore | Should -Match 'tools/plan-review/browser/screenshots'
    }

    It 'Should declare its dependencies inside the optional package only' {
        $manifest = Get-Content -LiteralPath (Join-Path $script:planReviewRoot 'package.json') -Raw | ConvertFrom-Json

        $manifest.private | Should -BeTrue
        $manifest.dependencies.PSObject.Properties.Name | Should -Contain 'markdown-it'
        $manifest.dependencies.PSObject.Properties.Name | Should -Contain 'mermaid'
        $manifest.dependencies.PSObject.Properties.Name | Should -Contain 'dompurify'
        Test-Path -LiteralPath (Join-Path $script:repoRoot 'package.json') | Should -BeFalse
    }
}

Describe 'Plan review trust boundaries' -Tag 'Unit' {
    It 'Should bind to loopback and refuse anything else' {
        $script:serverText | Should -Match 'isLoopbackAddress\(host\)'
        $script:serverText | Should -Match 'must bind to a loopback address'
        $script:serverText | Should -Not -Match "0\.0\.0\.0"
    }

    It 'Should send a strict content security policy with no script relaxation' {
        $script:serverText | Should -Match "default-src 'none'"
        $script:serverText | Should -Match "script-src 'self'"
        $script:serverText | Should -Match "frame-ancestors 'none'"
        $script:serverText | Should -Not -Match 'unsafe-eval'
        $script:serverText | Should -Not -Match "script-src 'self' 'unsafe-inline'"
    }

    It 'Should gate every mutation on Host, Origin, session and CSRF' {
        $script:serverText | Should -Match 'guardMutation\(request\.headers'

        $security = Get-Content -LiteralPath (Join-Path $script:sourceRoot 'security.mjs') -Raw

        foreach ($gate in 'checkHost', 'checkOrigin', 'checkFetchMetadata', 'checkContentType', 'checkSession', 'checkCsrf')
        {
            $security | Should -Match "$gate\(headers"
        }
    }

    It 'Should expose no command execution or arbitrary fetch path' {
        <#
            The lethal trifecta is broken by construction: untrusted document
            and comment text has no outbound channel and no executor. A single
            import of child_process or a server-side fetch would restore one.
        #>
        foreach ($file in $script:packageText)
        {
            $file.Text | Should -Not -Match 'child_process' -Because "$($file.Name) must not be able to run a command"
            $file.Text | Should -Not -Match 'node:vm|new Function\(|eval\(' -Because "$($file.Name) must not evaluate text"
        }

        $script:serverText | Should -Not -Match '(?m)^\s*(const|let)\s+.*=\s*await fetch\('
    }

    It 'Should serve only an allow-listed set of static files' {
        $script:serverText | Should -Match 'staticMap\.has\(path\)'
        $script:serverText | Should -Not -Match 'join\(.*request\.url'
        $script:serverText | Should -Not -Match 'readdir'
    }

    It 'Should never load a resource from a remote origin' {
        foreach ($file in $script:packageText)
        {
            $remote = [regex]::Matches($file.Text, 'https?://[^\s"''`)]+') |
                ForEach-Object -Process { $_.Value } |
                Where-Object -FilterScript {
                    $_ -notmatch '^http://127\.0\.0\.1' -and
                    $_ -notmatch '^http://\$\{' -and
                    $_ -notmatch '^http://www\.w3\.org/'
                }

            $remote | Should -BeNullOrEmpty -Because "$($file.Name) must not reference a remote resource"
        }
    }

    It 'Should disable raw HTML at the Markdown parser rather than filtering it' {
        $script:renderText | Should -Match 'html:\s*false'
        $script:renderText | Should -Match 'ALLOWED_URI_REGEXP'
        $script:renderText | Should -Match "FORBID_TAGS"
    }
}

Describe 'Plan review approval authority' -Tag 'Unit' {
    It 'Should record a browser verdict as feedback, never as sign-off' {
        $script:storeText | Should -Match "approvalAuthority: 'chat-sign-off-required'"
        $script:storeText | Should -Match "authority: 'local-http-feedback'"
        $script:serverText | Should -Match "approvalAuthority: 'chat-sign-off-required'"
    }

    It 'Should refuse a state root inside the Decision record folder' {
        $script:storeText | Should -Match 'isInsideDecisionFolder'

        $paths = Get-Content -LiteralPath (Join-Path $script:sourceRoot 'paths.mjs') -Raw
        $paths | Should -Match "'\.memory-bank'"
        $paths | Should -Match "'decisions'"
    }

    It 'Should never write into the Memory Bank or trigger a handoff' {
        foreach ($file in $script:packageText)
        {
            $file.Text | Should -Not -Match 'decisions/\d' -Because "$($file.Name) must not touch a Decision record"
            $file.Text | Should -Not -Match 'handoff' -Because "$($file.Name) must not start an unattended handoff"
        }
    }

    It 'Should say in the interface that approval stays in chat' {
        $shell = Get-Content -LiteralPath (Join-Path $script:assetRoot 'app.html') -Raw

        $shell | Should -Match 'review input only'
        $shell | Should -Match 'sign-off in chat'
    }
}

Describe 'Plan review containment' -Tag 'Unit' {
    It 'Should reject a reparse point anywhere between the root and the file' {
        $paths = Get-Content -LiteralPath (Join-Path $script:sourceRoot 'paths.mjs') -Raw

        $paths | Should -Match 'assertNoReparsePoint'
        $paths | Should -Match 'isSymbolicLink\(\)'
        $paths | Should -Match 'realpathSync\.native'
    }

    It 'Should authorize documents at launch and address them by an opaque identifier' {
        $script:serverText | Should -Match 'DOCUMENT_ID_PATTERN = /\^\[0-9a-f\]\{16\}\$/'
        $script:serverText | Should -Match 'registry\.get\(documentId\)'
    }
}

Describe 'Plan review demonstration sample' -Tag 'Unit' {
    BeforeAll {
        $script:samplePath = Join-Path $script:planReviewRoot 'samples/design-concept-sample.md'
        $script:sampleText = Get-Content -LiteralPath $script:samplePath -Raw
    }

    It 'Should ship a sample that renders a real diagram' {
        $script:sampleText | Should -Match '(?m)^```mermaid\s*$'
        $script:sampleText | Should -Match 'flowchart TD'
    }

    It 'Should mark the sample as a demonstration rather than approved work' {
        $script:sampleText | Should -Match '(?i)DEMONSTRATION ONLY'
        $script:sampleText | Should -Match '(?i)approving it in the browser approves nothing'
    }

    It 'Should keep the sample out of the Memory Bank' {
        $script:samplePath | Should -Not -Match '\.memory-bank'
        Test-Path -LiteralPath (Join-Path $script:repoRoot '.memory-bank/decisions/design-concept-sample.md') |
            Should -BeFalse
    }
}

Describe 'Plan review documentation and workflow reference' -Tag 'Unit' {
    It 'Should document setup, boundaries, storage, shutdown and rollback' {
        $guide = Get-Content -LiteralPath (Join-Path $script:repoRoot 'docs/plan-review.md') -Raw

        foreach ($heading in 'Setup', 'Trust boundaries', 'Where state lives', 'Shutdown', 'Rollback', 'Unsupported')
        {
            $guide | Should -Match "(?m)^#{2,3}\s+$heading"
        }
    }

    It 'Should keep the threat model alongside it' {
        Test-Path -LiteralPath (Join-Path $script:repoRoot 'docs/plan-review-threat-model.md') | Should -BeTrue
    }

    It 'Should reference the optional surface from the architect workflow without granting it authority' {
        $agent = Get-Content -LiteralPath (Join-Path $script:repoRoot 'com.github.copilot/agents/software-architect.agent.md') -Raw

        $agent | Should -Match 'plan-review'
        $agent | Should -Match '(?i)does not replace the sign-off'
    }

    It 'Should leave the architect agent frontmatter grants untouched' {
        <#
            The strict client-adapter parser rejects an unknown or duplicate
            frontmatter field, so this reference must be body prose only.
        #>
        $agentLine = @(Get-Content -LiteralPath (Join-Path $script:repoRoot 'com.github.copilot/agents/software-architect.agent.md'))
        $delimiter = @(0..($agentLine.Count - 1) | Where-Object -FilterScript { $agentLine[$_] -eq '---' })
        $frontmatter = $agentLine[($delimiter[0] + 1)..($delimiter[1] - 1)] -join "`n"

        $frontmatter | Should -Not -Match 'plan-review'
        $frontmatter | Should -Match "(?m)^tools: \["
        $frontmatter | Should -Match "(?m)^handoffs:"
    }

    It 'Should announce the feature in the changelog' {
        $changelog = Get-Content -LiteralPath (Join-Path $script:repoRoot 'CHANGELOG.md') -Raw

        $changelog | Should -Match 'tools/plan-review'
        $changelog | Should -Match 'docs/plan-review\.md'
    }
}

Describe 'Plan review Node suite' -Tag 'Unit' {
    It 'Should run <Name> without any installed dependency' -Skip:(-not $script:nodeAvailable) -ForEach $script:nodeUnitCase {
        <#
            These files import only src modules that have no third-party
            imports, so the repository gate can execute them without an
            `npm install` ever having run.
        #>
        Push-Location -LiteralPath $script:planReviewRoot

        try
        {
            $output = & node --test --test-reporter tap $RelativePath 2>&1 |
                ForEach-Object -Process { [string]$_ }
            $exitCode = $LASTEXITCODE
        }
        finally
        {
            Pop-Location
        }

        $exitCode | Should -Be 0 -Because ($output -join [System.Environment]::NewLine)
    }
}
