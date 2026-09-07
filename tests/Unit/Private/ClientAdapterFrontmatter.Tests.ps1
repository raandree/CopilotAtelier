BeforeAll {
    $script:projectPath = Convert-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')
    . (Join-Path $script:projectPath 'tests/Helpers/DeploymentProfile.ps1')
    Import-CopilotAtelierTestModule -ProjectPath $script:projectPath

    function script:Read-Frontmatter
    {
        [CmdletBinding()]
        param
        (
            [Parameter(Mandatory)]
            [AllowEmptyString()]
            [string]$Content,

            [Parameter()]
            [string[]]$KnownField
        )

        InModuleScope CopilotAtelier -Parameters @{ Content = $Content; KnownField = $KnownField } {
            param ($Content, $KnownField)

            $splat = @{
                Content = $Content
                Source  = 'fixture.agent.md'
            }

            if ($KnownField)
            {
                $splat['KnownField'] = $KnownField
            }

            ConvertFrom-CopilotAtelierAgentFrontmatter @splat
        }
    }
}

Describe 'Strict agent frontmatter parsing' -Tag 'Unit' {
    It 'Should decode a single-quoted scalar that carries an escaped quote' {
        $content = "---`nname: fixture`ndescription: 'Bloom''s taxonomy'`n---`n# Body`n"

        $result = script:Read-Frontmatter -Content $content

        $result.Field['description'].Type | Should -Be 'String'
        $result.Field['description'].Value | Should -BeExactly "Bloom's taxonomy"
    }

    It 'Should decode a <Style> tool list rather than ignoring it' -ForEach @(
        @{ Style = 'single-quoted flow'; Line = "tools: ['read/readFile', 'edit/editFiles']" }
        @{ Style = 'double-quoted flow'; Line = 'tools: ["read/readFile", "edit/editFiles"]' }
        @{ Style = 'plain flow'; Line = 'tools: [read/readFile, edit/editFiles]' }
        @{ Style = 'block sequence'; Line = "tools:`n  - read/readFile`n  - edit/editFiles" }
    ) {
        <#
            A regular expression that only finds single-quoted items silently
            produces an empty tool list for the other three valid styles, which
            composes a profile with no capabilities at all.
        #>
        $content = "---`nname: fixture`n$Line`n---`n# Body`n"

        $result = script:Read-Frontmatter -Content $content

        $result.Field['tools'].Type | Should -Be 'Sequence'
        @($result.Field['tools'].Value) | Should -Be @('read/readFile', 'edit/editFiles')
    }

    It 'Should decode a plain boolean without quoting it back into a string' {
        $content = "---`nname: fixture`ndisable-model-invocation: true`n---`n# Body`n"

        $result = script:Read-Frontmatter -Content $content

        $result.Field['disable-model-invocation'].Type | Should -Be 'Boolean'
        $result.Field['disable-model-invocation'].Value | Should -BeTrue
    }

    It 'Should classify a nested block such as handoffs as structured and keep it visible' {
        $content = "---`nname: fixture`nhandoffs:`n  - label: Run Security Review`n    agent: security-reviewer`n---`n# Body`n"

        $result = script:Read-Frontmatter -Content $content

        $result.Field['handoffs'].Type | Should -Be 'Structured'
        @($result.Field.Keys) | Should -Contain 'handoffs'
    }

    It 'Should reject a duplicate top-level field instead of letting the last one win' {
        $content = "---`nname: fixture`ntools: ['read/readFile']`ntools: ['execute/runInTerminal']`n---`n# Body`n"

        { script:Read-Frontmatter -Content $content } | Should -Throw -ExpectedMessage '*tools*'
    }

    It 'Should reject an unknown top-level field so a new safety field cannot vanish' {
        $content = "---`nname: fixture`ndeny-tools: ['execute/runInTerminal']`n---`n# Body`n"

        { script:Read-Frontmatter -Content $content } | Should -Throw -ExpectedMessage '*deny-tools*'
    }

    It 'Should reject <Case> rather than guess at its meaning' -ForEach @(
        @{ Case = 'a folded block scalar'; Line = "description: >-`n  Wrapped text" }
        @{ Case = 'a literal block scalar'; Line = "description: |`n  Wrapped text" }
        @{ Case = 'an anchor'; Line = 'name: &anchor fixture' }
        @{ Case = 'an alias'; Line = 'name: *anchor' }
        @{ Case = 'an explicit tag'; Line = 'name: !!str fixture' }
        @{ Case = 'a flow mapping'; Line = 'name: { value: fixture }' }
        @{ Case = 'an unterminated flow sequence'; Line = "tools: ['read/readFile'" }
        @{ Case = 'an unbalanced quote'; Line = "name: 'fixture" }
        @{ Case = 'a trailing comment on a plain scalar'; Line = 'name: fixture # really' }
    ) {
        $content = "---`n$Line`n---`n# Body`n"

        { script:Read-Frontmatter -Content $content -KnownField @('name', 'description', 'tools') } |
            Should -Throw
    }

    It 'Should reject frontmatter without a closing delimiter' {
        $content = "---`nname: fixture`n# Body`n"

        { script:Read-Frontmatter -Content $content } | Should -Throw -ExpectedMessage '*delimiter*'
    }

    It 'Should reject content that does not open with a frontmatter delimiter' {
        { script:Read-Frontmatter -Content "# Body`n" } | Should -Throw -ExpectedMessage '*delimiter*'
    }

    It 'Should keep the body byte for byte after normalizing line endings' {
        $body = "# Body`n`nRun the tests.`n"
        $content = "---`r`nname: fixture`r`n---`r`n" + ($body -replace "`n", "`r`n")

        $result = script:Read-Frontmatter -Content $content

        $result.Body | Should -BeExactly $body
    }

    It 'Should accept an empty sequence without inventing a value' {
        $content = "---`nname: fixture`nagents: []`n---`n# Body`n"

        $result = script:Read-Frontmatter -Content $content

        $result.Field['agents'].Type | Should -Be 'Sequence'
        @($result.Field['agents'].Value).Count | Should -Be 0
    }
}
