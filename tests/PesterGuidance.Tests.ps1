BeforeDiscovery {
    $script:guidanceCases = @(
        @{
            Name = 'Pester Instruction'
            Segments = @('com.github.copilot', 'rules', 'pester.instructions.md')
            GuardCount = 6
        }
        @{
            Name = 'Pester patterns Skill'
            Segments = @('skills', 'pester-patterns', 'SKILL.md')
            GuardCount = 3
        }
        @{
            Name = 'Pester migration reference'
            Segments = @('skills', 'pester-patterns', 'references', 'migrating-pester-v4-to-v5.md')
            GuardCount = 1
        }
    )
}

Describe 'Detached Pester guidance' -Tag 'Unit' {
    BeforeAll {
        $script:guidanceRoot = Split-Path -Parent $PSScriptRoot

        function Get-PesterGuidance {
            [CmdletBinding()]
            [OutputType([pscustomobject])]
            param(
                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [string[]] $Segments
            )

            $path = $script:guidanceRoot
            foreach ($segment in $Segments) {
                $path = Join-Path -Path $path -ChildPath $segment
            }
            # The launcher here-string escapes dollars; compile its actual child guards.
            $content = (Get-Content -LiteralPath $path -Raw -Encoding UTF8).Replace('`$', '$')
            $pattern = '(?ms)if\s*\((?<Condition>[^)]*\$result\.(?:FailedCount|Result)[^)]*)\)' +
                '\s*\{(?<Body>\s*throw[^\r\n]*)(?:\r?\n\s*)?\}'

            [pscustomobject]@{
                Content = $content
                Guards = @([regex]::Matches($content, $pattern))
            }
        }
    }

    Context '<Name>' -ForEach $script:guidanceCases {
        BeforeAll {
            $script:guidance = Get-PesterGuidance -Segments $Segments
        }

        It 'retains every detached result guard' {
            $script:guidance.Guards.Count | Should -Be $GuardCount
        }

        It 'fails the run on Result rather than only FailedCount' {
            foreach ($guard in $script:guidance.Guards) {
                $guard.Groups['Condition'].Value.Trim() | Should -Be '$result.Result -ne ''Passed'''
            }
            $script:guidance.Content | Should -Not -Match 'throw when\s+`?\$result\.FailedCount'
        }

        It 'names the result and every failure count in each diagnostic' {
            foreach ($guard in $script:guidance.Guards) {
                foreach ($field in 'Result', 'FailedCount', 'FailedBlocksCount', 'FailedContainersCount') {
                    $guard.Groups['Body'].Value | Should -Match "$field="
                    $guard.Groups['Body'].Value | Should -Match ('\$result\.' + $field)
                }
            }
        }

        It 'rejects a failed container even when no test failed' {
            $result = [pscustomobject]@{
                Result = 'Failed'
                FailedCount = 0
                FailedBlocksCount = 0
                FailedContainersCount = 1
            }
            foreach ($guard in $script:guidance.Guards) {
                $code = [scriptblock]::Create('param($result) ' + $guard.Value)
                { & $code $result } | Should -Throw '*FailedContainersCount=1*'
            }
        }

        It 'rejects a run that returned nothing' {
            foreach ($guard in $script:guidance.Guards) {
                $code = [scriptblock]::Create('param($result) ' + $guard.Value)
                { & $code $null } | Should -Throw '*Result=*'
            }
        }

        It 'preserves a Passed result with zero executed tests' {
            $result = [pscustomobject]@{
                Result = 'Passed'
                FailedCount = 0
                FailedBlocksCount = 0
                FailedContainersCount = 0
            }
            foreach ($guard in $script:guidance.Guards) {
                $code = [scriptblock]::Create('param($result) ' + $guard.Value)
                { & $code $result } | Should -Not -Throw
            }
        }
    }
}
