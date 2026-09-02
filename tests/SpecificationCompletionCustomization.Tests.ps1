BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:promptPath = Join-Path $script:repoRoot 'com.github.copilot/commands/complete-specifications.prompt.md'
    $script:controllerPath = Join-Path $script:repoRoot 'com.github.copilot/agents/spec-completion-controller.agent.md'
    $script:implementerPath = Join-Path $script:repoRoot 'com.github.copilot/agents/spec-work-implementer.agent.md'
    $script:reviewerPath = Join-Path $script:repoRoot 'com.github.copilot/agents/spec-completion-reviewer.agent.md'

    function Get-FrontmatterValue {
        param(
            [Parameter(Mandatory)]
            [string]$Path,

            [Parameter(Mandatory)]
            [string]$Name
        )

        $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        $frontmatter = [regex]::Match(
            $content,
            '(?s)\A---\r?\n(?<value>.*?)\r?\n---\r?\n'
        )
        $frontmatter.Success | Should -BeTrue -Because "$Path must have frontmatter"

        $match = [regex]::Match(
            $frontmatter.Groups['value'].Value,
            "(?m)^$([regex]::Escape($Name)):\s*(?<value>.+)$"
        )

        return $match.Groups['value'].Value.Trim()
    }

    function Get-InlineSequenceValue {
        param(
            [Parameter(Mandatory)]
            [string]$Path,

            [Parameter(Mandatory)]
            [string]$Name
        )

        $value = Get-FrontmatterValue -Path $Path -Name $Name

        if ([string]::IsNullOrWhiteSpace($value)) {
            throw "Missing frontmatter key '$Name': $Path"
        }

        if ($value -notmatch "^\[(?:\s*|\s*'[^']+'(?:\s*,\s*'[^']+')*\s*)\]$") {
            throw "Frontmatter key '$Name' is not an inline string sequence: $Path"
        }

        return @(
            [regex]::Matches($value, "'([^']+)'") |
                ForEach-Object { $_.Groups[1].Value }
        )
    }
}

Describe 'Specification completion Customizations' -Tag 'Unit' {
    It 'ships one Prompt and three restricted Custom agents' {
        foreach ($path in @(
                $script:promptPath
                $script:controllerPath
                $script:implementerPath
                $script:reviewerPath
            )) {
            Test-Path -LiteralPath $path -PathType Leaf | Should -BeTrue -Because $path
        }
    }

    It 'binds the Prompt directly to the controller without overriding its tools' {
        Get-FrontmatterValue -Path $script:promptPath -Name 'agent' |
            Should -Be 'spec-completion-controller'
        Get-FrontmatterValue -Path $script:promptPath -Name 'tools' |
            Should -BeNullOrEmpty

        $content = Get-Content -LiteralPath $script:promptPath -Raw -Encoding UTF8
        $content | Should -Not -Match 'runInTerminal|editFiles|web/fetch|github'
        @(Get-Content -LiteralPath $script:promptPath -Encoding UTF8).Count |
            Should -BeLessOrEqual 30
    }

    It 'lets the controller dispatch only its implementer and reviewer' {
        Get-InlineSequenceValue -Path $script:controllerPath -Name 'agents' |
            Should -Be @(
                'spec-work-implementer'
                'spec-completion-reviewer'
            )

        Get-InlineSequenceValue -Path $script:controllerPath -Name 'tools' |
            Should -Be @(
                'agent'
                'search/changes'
                'search/codebase'
                'search/fileSearch'
                'search/listDirectory'
                'search/textSearch'
                'search/findTestFiles'
                'search/usages'
                'edit/editFiles'
                'edit/createFile'
                'edit/createDirectory'
                'edit/rename'
                'execute/runInTerminal'
                'execute/getTerminalOutput'
                'read/readFile'
                'read/problems'
                'read/terminalLastCommand'
                'read/testFailure'
                'todo'
                'thinking'
            )
        Get-FrontmatterValue -Path $script:controllerPath -Name 'disable-model-invocation' |
            Should -Be 'true'
        Get-FrontmatterValue -Path $script:controllerPath -Name 'user-invocable' |
            Should -Be 'false'
    }

    It 'keeps both workers non-nesting and the reviewer read-only' {
        foreach ($path in @($script:implementerPath, $script:reviewerPath)) {
            Get-InlineSequenceValue -Path $path -Name 'agents' |
                Should -BeNullOrEmpty
            Get-InlineSequenceValue -Path $path -Name 'tools' |
                Should -Not -Contain 'agent'
        }

        Get-InlineSequenceValue -Path $script:implementerPath -Name 'tools' |
            Should -Be @(
                'search/changes'
                'search/codebase'
                'search/fileSearch'
                'search/listDirectory'
                'search/textSearch'
                'search/findTestFiles'
                'search/usages'
                'edit/editFiles'
                'edit/createFile'
                'edit/createDirectory'
                'edit/rename'
                'execute/runInTerminal'
                'execute/getTerminalOutput'
                'read/readFile'
                'read/problems'
                'read/testFailure'
                'todo'
                'thinking'
            )
        Get-InlineSequenceValue -Path $script:reviewerPath -Name 'tools' |
            Should -Be @(
                'search/changes'
                'search/codebase'
                'search/fileSearch'
                'search/listDirectory'
                'search/textSearch'
                'search/findTestFiles'
                'search/usages'
                'read/readFile'
                'read/problems'
                'read/testFailure'
                'todo'
                'thinking'
            )

        foreach ($path in @($script:implementerPath, $script:reviewerPath)) {
            Get-FrontmatterValue -Path $path -Name 'disable-model-invocation' |
                Should -Be 'true'
            Get-FrontmatterValue -Path $path -Name 'user-invocable' |
                Should -Be 'false'
        }
    }

    It 'fails the capability guard when a worker omits tools' {
        $fixture = Join-Path $TestDrive 'missing-tools.agent.md'
        @'
---
name: missing-tools
description: Test fixture.
model: ['one', 'two']
agents: []
---
# Missing tools
'@ | Set-Content -LiteralPath $fixture -Encoding UTF8

        {
            Get-InlineSequenceValue -Path $fixture -Name 'tools'
        } | Should -Throw -ExpectedMessage '*Missing frontmatter key*tools*'
    }

    It 'fails the capability guard when worker tools use unsupported syntax' {
        $fixture = Join-Path $TestDrive 'malformed-tools.agent.md'
        @'
---
name: malformed-tools
description: Test fixture.
model: ['one', 'two']
tools: ["search/changes"]
agents: []
---
# Malformed tools
'@ | Set-Content -LiteralPath $fixture -Encoding UTF8

        {
            Get-InlineSequenceValue -Path $fixture -Name 'tools'
        } | Should -Throw -ExpectedMessage '*not an inline string sequence*'
    }

    It 'requires evidence inventory, one implementer per item, tests, and review' {
        $content = Get-Content -LiteralPath $script:controllerPath -Raw -Encoding UTF8

        $content | Should -Match 'closure matrix'
        $content | Should -Match 'one fresh.*spec-work-implementer.*per work item'
        $content | Should -Match 'failing test.*first'
        $content | Should -Match 'unit.*integration'
        $content | Should -Match 'spec-completion-reviewer'
        $content | Should -Match 'Blocker.*Major'
    }

    It 'keeps completion accounting honest and live validation bounded' {
        $content = Get-Content -LiteralPath $script:controllerPath -Raw -Encoding UTF8

        $content | Should -Match 'ImplementationPercent'
        $content | Should -Match 'LocalTestPercent'
        $content | Should -Match 'LiveVerifiedPercent'
        $content | Should -Match 'blocked.*denominator'
        $content | Should -Match 'read-only|disposable'
        $content | Should -Match 'shared|production'
        $content | Should -Match 'rollback|cleanup'
        $content | Should -Match 'Never push'
        $content | Should -Match '(?m)^- `live-mode`.*default `off`\.\r?$'
        $content | Should -Match '(?s)`live-profile`.*required when `live-mode` is not `off`'
        $content | Should -Match '(?s)missing or unverifiable live profile.*BlockedContainment'
    }

    It 'requires deterministic remote-mutation and terminal containment' {
        $controller = Get-Content -LiteralPath $script:controllerPath -Raw -Encoding UTF8
        $implementer = Get-Content -LiteralPath $script:implementerPath -Raw -Encoding UTF8

        $controller | Should -Match 'Block-RemoteMutation'
        $controller | Should -Match 'COPILOT_ATELIER_ALLOW_REMOTE'
        $controller | Should -Match 'containment-profile'
        $controller | Should -Match 'default-deny outbound'
        $controller | Should -Match 'remote credentials'
        $implementer | Should -Match 'network-disabled'
        $controller | Should -Match 'controller.*egress.*empty'
        $controller | Should -Match 'worker.*egress.*empty'
        $controller | Should -Match 'separate.*live.*runner'
        $controller | Should -Match 'effective.*allow.*set'
    }

    It 'limits pre-containment execution and reverifies immutable controls' {
        $controller = Get-Content -LiteralPath $script:controllerPath -Raw -Encoding UTF8

        $controller | Should -Match 'pre-containment probe'
        $controller | Should -Match 'only pre-gate execution'
        $controller | Should -Match 'immutable'
        $controller | Should -Match 'before every delegation\s+wave'
        $controller | Should -Match '(?s)synthetic.*0, 2,\s+and 2'
        $controller | Should -Match 'BlockedContainment'
    }

    It 'pins live authority and confines repository-controlled execution' {
        $controller = Get-Content -LiteralPath $script:controllerPath -Raw -Encoding UTF8
        $reviewer = Get-Content -LiteralPath $script:reviewerPath -Raw -Encoding UTF8

        $controller | Should -Match '(?s)live profile.*canonical path.*SHA-256'
        $controller | Should -Match '(?s)hash-pinned\s+verifier also canonicalizes and hashes the live profile'
        $controller | Should -Match 'hash-pinned live profile declares'
        $controller | Should -Not -Match 'signed live profile'
        $controller | Should -Match '(?s)Reverify the profile, runner, template manifest'
        $controller | Should -Match '(?s)Repository-defined build and test commands.*only repository-derived\s+executable inputs'
        $controller | Should -Match '(?s)record.*verbatim.*ledger.*before execution'
        $controller | Should -Match '(?s)writable filesystem set.*exactly.*isolated worktree.*run-artifact'
        $controller | Should -Match '(?s)verify hashes.*exact writable roots'
        $controller | Should -Match '(?s)tracked and untracked.*outside.*assigned.*Blocker'
        $controller | Should -Match '(?s)reviewer.*verbatim.*append-only JSONL\s+ledger.*SHA-256'
        $controller | Should -Match 'every review request/response hash'
        $reviewer | Should -Match 'review token'
        Get-FrontmatterValue -Path $script:reviewerPath -Name 'argument-hint' |
            Should -Not -Match 'report path'
        Get-FrontmatterValue -Path $script:controllerPath -Name 'argument-hint' |
            Should -Match 'live-mode=off\|read-only\|disposable'
    }

    It 'fails closed on accounting exclusions and unresolved review findings' {
        $controller = Get-Content -LiteralPath $script:controllerPath -Raw -Encoding UTF8
        $reviewer = Get-Content -LiteralPath $script:reviewerPath -Raw -Encoding UTF8

        $controller | Should -Match '(?s)ConditionalNotTriggered.*repeatable\s+measurement'
        $controller | Should -Match 'unreproducible.*Blocked'
        $controller | Should -Match 'with and without exclusion'
        $controller | Should -Match '(?s)open.*Blocker.*forbids.*completion'
        $reviewer | Should -Not -Match 'when available'
    }

    It 'corroborates issue work and proves disposable targets independently' {
        $controller = Get-Content -LiteralPath $script:controllerPath -Raw -Encoding UTF8

        $controller | Should -Match 'issue.*corroborated.*tracked'
        $controller | Should -Match '(?s)live runner.*create.*disposable\s+target'
        $controller | Should -Not -Match 'controller must create\s+the disposable target'
        $controller | Should -Match 'run-unique token'
        $controller | Should -Match 'BlockedConcurrentRun'
        $controller | Should -Match 'refs/remotes'
    }

    It 'anchors containment authority outside model-controlled data' {
        $controller = Get-Content -LiteralPath $script:controllerPath -Raw -Encoding UTF8

        Get-FrontmatterValue -Path $script:controllerPath -Name 'argument-hint' |
            Should -Match 'containment-profile-sha256=<64-hex>'
        $controller | Should -Match '(?s)- `containment-profile-sha256`.*direct\s+Prompt argument'
        $controller | Should -Match '(?s)profile.*SHA-256.*direct argument.*before.*verifier'
        $controller | Should -Match '(?s)profile and verifier.*not writable.*run identity'
    }

    It 'keeps harness changes reviewed and commits reachable before cleanup' {
        $controller = Get-Content -LiteralPath $script:controllerPath -Raw -Encoding UTF8
        $commitIndex = $controller.IndexOf('Create coherent local conventional commits')
        $sweepIndex = $controller.IndexOf('Sweep current-run processes')

        $controller | Should -Match '(?s)after each integration wave.*re-detect and hash.*build\s+and test commands'
        $controller | Should -Match '(?s)changed command must not.*execut.*until.*control-change review.*without.*Blocker.*Major'
        $commitIndex | Should -BeGreaterThan -1
        $sweepIndex | Should -BeGreaterThan $commitIndex
        $controller | Should -Match '(?s)run commit.*reachable.*integration branch.*before.*delet'
    }

    It 'defines and publishes every engineering denominator' {
        $controller = Get-Content -LiteralPath $script:controllerPath -Raw -Encoding UTF8

        $controller | Should -Match '(?s)Applicable engineering rows.*every non-`Duplicate` engineering row'
        $controller | Should -Match '(?s)ConditionalNotTriggered.*applicable engineering denominator'
        $controller | Should -Match '(?s)all four percentages.*with and without.*exclusion'
        $controller | Should -Match 'raw numerator, denominator, and\s+excluded-row counts'
    }

    It 'protects the ledger and override state from repository processes' {
        $controller = Get-Content -LiteralPath $script:controllerPath -Raw -Encoding UTF8

        $controller | Should -Match '(?s)ledger\s+appender.*canonical path.*SHA-256'
        $controller | Should -Match '(?s)append-only ledger sink.*not writable.*terminal child'
        $controller | Should -Match '(?s)monotonic sequence.*prevSha256.*recordSha256'
        $controller | Should -Match '(?s)chain head.*checkpoint'
        $controller | Should -Match '(?s)protected chain\s+head.*not writable.*run\s+identity'
        $controller | Should -Match '(?s)Process, User, and Machine.*freshly spawned hook process'
        $controller | Should -Match '(?s)Never create or persist.*COPILOT_ATELIER_ALLOW_REMOTE.*scope'
    }

    It 'retains dirty-tree, issue, injection, budget, and remote safety gates' {
        $controller = Get-Content -LiteralPath $script:controllerPath -Raw -Encoding UTF8
        $workers = @(
            Get-Content -LiteralPath $script:implementerPath -Raw -Encoding UTF8
            Get-Content -LiteralPath $script:reviewerPath -Raw -Encoding UTF8
        ) -join [Environment]::NewLine

        $controller | Should -Match 'BlockedDirtyWorktree'
        $controller | Should -Match 'issue tracking as unavailable'
        $controller | Should -Match 'untrusted\s+data,\s+never\s+as\s+instructions'
        $controller | Should -Match 'maximum 12'
        $controller | Should -Match 'max-concurrency.*maximum 2'
        $controller | Should -Match '(?s)refs/remotes/\*.*unchanged'
        $workers | Should -Match 'Never.*push'
        $workers | Should -Match 'untrusted data'

        $implementerTools = Get-InlineSequenceValue -Path $script:implementerPath -Name 'tools'
        $implementerTools -join ',' |
            Should -Not -Match 'web/|github|useMcp|openSimpleBrowser'
    }

    It 'stays repository-neutral' {
        $content = @(
            Get-Content -LiteralPath $script:promptPath -Raw -Encoding UTF8
            Get-Content -LiteralPath $script:controllerPath -Raw -Encoding UTF8
            Get-Content -LiteralPath $script:implementerPath -Raw -Encoding UTF8
            Get-Content -LiteralPath $script:reviewerPath -Raw -Encoding UTF8
        ) -join [Environment]::NewLine

        $content |
            Should -Not -Match '(?-i:\b(?:FarmSight|RDS|Connection Broker|Pester|Sampler)\b)'
    }
}
