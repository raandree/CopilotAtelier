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
        <#
            This is a source-shape tripwire on the gate composition: a check
            that is defined but not in the gate array is not applied. The
            behavioural regression that fails when a gate stops being applied is
            tools/plan-review/test/unit/mutation-gate.test.mjs, which the Node
            suite below runs without any installed dependency.
        #>
        $script:serverText | Should -Match 'guardMutation\(request\.headers'

        $security = Get-Content -LiteralPath (Join-Path $script:sourceRoot 'security.mjs') -Raw
        $gate = [regex]::Match($security, 'function guardMutation[\s\S]*?const gate = \[([\s\S]*?)\r?\n\s*\]')

        $gate.Success | Should -BeTrue -Because 'every mutation clears the gate array, not the definitions'

        foreach ($check in 'checkHost', 'checkOrigin', 'checkFetchMetadata', 'checkContentType', 'checkSession', 'checkCsrf')
        {
            $gate.Groups[1].Value | Should -Match "$check\(headers" -Because 'a check removed from the gate array is no longer applied'
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

    It 'Should hold application assets as an immutable launch snapshot' {
        <#
            A document is re-read on every request because it is the thing under
            review. The page's own assets are not: serving them from a snapshot
            keeps a file swapped or deleted after launch from changing what the
            page runs or hanging a request on a broken read stream.
        #>
        $script:serverText | Should -Match 'function snapshotAsset'
        $script:serverText | Should -Match 'MAX_ASSET_BYTES'
        $script:serverText | Should -Not -Match 'createReadStream'
    }

    It 'Should namespace the session cookie per launch' {
        <#
            Cookies are scoped by host, not by port, so a fixed name lets a
            second local server overwrite the first server's session.
        #>
        $security = Get-Content -LiteralPath (Join-Path $script:sourceRoot 'security.mjs') -Raw

        $security | Should -Match 'export function sessionCookieName'
        $security | Should -Not -Match "SESSION_COOKIE_NAME = 'plan_review_session'"
        $script:serverText | Should -Match 'sessionCookieName\(serverId\)'
    }

    It 'Should derive the allowed authority from the address actually bound' {
        $script:serverText | Should -Match 'formatAuthority\(address\.address, address\.port\)'
        $script:serverText | Should -Not -Match '`127\.0\.0\.1:\$\{'
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
        $script:storeText | Should -Match "FEEDBACK_AUTHORITY = 'local-http-feedback'"
        $script:storeText | Should -Match 'authority: FEEDBACK_AUTHORITY'
        $script:serverText | Should -Match "approvalAuthority: 'chat-sign-off-required'"
    }

    It 'Should refuse to read a stored authority as anything better than feedback' {
        $script:storeText | Should -Match 'verdict\.authority === FEEDBACK_AUTHORITY'
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

    It 'Should verify every document read against the Markdown parser' {
        <#
            The behavioural proof needs markdown-it, so it lives in
            test/integration/heading-verification.test.mjs and this
            dependency-free gate cannot run it. A read that skips the verifier
            anchors feedback to text the reader never saw, so the wiring is
            asserted from the source here. The call sites are one line each; a
            reformat that breaks this also fails the mandatory-argument check
            in test/unit/document.test.mjs, which the gate does run.
        #>
        $script:serverText | Should -Match "import \{ createHeadingVerifier \} from './headings\.mjs'"
        $script:serverText | Should -Match 'const verifyHeadings = createHeadingVerifier\(\)'

        $readSite = @(
            [regex]::Matches($script:serverText, '(?m)^.*\bloadDocument(?:Sync)?\(.*$') |
                ForEach-Object -Process { $_.Value.Trim() }
        )

        $readSite | Should -Not -BeNullOrEmpty -Because 'the server must still read the document under review'

        foreach ($site in $readSite)
        {
            $site | Should -Match 'verifyHeadings' -Because 'an unverified read can anchor feedback to unrendered text'
        }

        $headings = Get-Content -LiteralPath (Join-Path $script:sourceRoot 'headings.mjs') -Raw

        $headings | Should -Match "'heading-structure'"
        $headings | Should -Match 'token\.level !== 0'
    }

    It 'Should recheck the source revision inside the serialized mutation' {
        $script:serverText | Should -Match "'stale-source'"
        $script:serverText | Should -Match '\{ precondition \}'
        $script:storeText | Should -Match 'await precondition\(record\)'
    }

    It 'Should preserve unreadable feedback rather than overwriting it' {
        $script:storeText | Should -Match 'unreadableReason'
        $script:storeText | Should -Match 'MAX_STORE_BYTES'
        $script:storeText | Should -Not -Match 'rmSync'
        $script:storeText | Should -Match "'lock-lost'"
    }

    It 'Should refuse to write a record its own reader would refuse' {
        $script:storeText | Should -Match "Buffer\.byteLength\(bytes, 'utf8'\) > MAX_STORE_BYTES"
        $script:storeText | Should -Match "'store-capacity'"
        $script:storeText | Should -Match 'SHA256_PATTERN = /\^\[0-9a-f\]\{64\}\$/'
        $script:storeText | Should -Match "'invalid-section-hash'"
        $script:storeText | Should -Match "'invalid-document-hash'"
    }

    It 'Should issue a section key that is unique across the whole document' {
        $document = Get-Content -LiteralPath (Join-Path $script:sourceRoot 'document.mjs') -Raw

        $document | Should -Match 'const used = new Set\(\)'
        $document | Should -Match 'while \(used\.has\(key\)\)'
        $document | Should -Match 'used\.add\(key\)'
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
