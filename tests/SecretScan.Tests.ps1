$script:repoRoot = Split-Path -Parent $PSScriptRoot

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot

    <#
        High-signal credential shapes only. A generic
        password/secret/token = "..." rule fires on placeholders, parameter
        names, and prose throughout the Skills, and a scanner that cries wolf
        gets suppressed rather than fixed.
    #>
    $script:secretRule = @(
        @{ Name = 'PrivateKeyBlock'; Pattern = '-----BEGIN [A-Z ]*PRIVATE KEY-----' }
        @{ Name = 'GitHubToken'; Pattern = 'gh[pousr]_[A-Za-z0-9]{36}' }
        @{ Name = 'GitHubFineGrainedToken'; Pattern = 'github_pat_[A-Za-z0-9_]{20,}' }
        @{ Name = 'AwsAccessKeyId'; Pattern = 'AKIA[0-9A-Z]{16}' }
        @{ Name = 'AzureStorageAccountKey'; Pattern = 'AccountKey=[A-Za-z0-9+/=]{40,}' }
        @{ Name = 'SlackToken'; Pattern = 'xox[baprs]-[A-Za-z0-9-]{10,}' }
    )

    $script:binaryExtension = @(
        '.png', '.jpg', '.jpeg', '.gif', '.ico', '.svg', '.pdf', '.zip', '.nupkg'
        '.dll', '.exe', '.pfx', '.cer', '.woff', '.woff2', '.ttf', '.docx', '.xlsx'
    )

    function script:Get-SecretFinding
    {
        [CmdletBinding()]
        [OutputType([pscustomobject])]
        param
        (
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string[]]$Path,

            [Parameter()]
            [AllowEmptyCollection()]
            [string[]]$ExcludeFile = @()
        )

        foreach ($currentPath in $Path)
        {
            if (-not (Test-Path -LiteralPath $currentPath))
            {
                continue
            }

            $file = if (Test-Path -LiteralPath $currentPath -PathType Leaf)
            {
                Get-Item -LiteralPath $currentPath -Force
            }
            else
            {
                Get-ChildItem -LiteralPath $currentPath -Recurse -File -Force
            }

            foreach ($currentFile in $file)
            {
                if ($ExcludeFile -contains $currentFile.FullName -or
                    $currentFile.Extension -in $script:binaryExtension -or
                    $currentFile.Length -gt 1MB)
                {
                    continue
                }

                $content = Get-Content -LiteralPath $currentFile.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue

                if ([string]::IsNullOrEmpty($content))
                {
                    continue
                }

                foreach ($rule in $script:secretRule)
                {
                    foreach ($match in [regex]::Matches($content, $rule.Pattern))
                    {
                        [pscustomobject]@{
                            Path = $currentFile.FullName
                            Line = ($content.Substring(0, $match.Index) -split "`n").Count
                            Rule = $rule.Name
                        }
                    }
                }
            }
        }
    }
}

Describe 'Secret scan' -Tag 'Unit' {
    It 'detects a planted credential' {
        <#
            The gate has to be shown to reject a bad input. Without this, a
            broken pattern list reports a clean repository forever.

            The sample values are assembled from fragments so the literals never
            appear in this file, which would otherwise be the scanner's only
            finding.
        #>
        $plantedFile = Join-Path $TestDrive 'planted.txt'
        @(
            'AKIA' + 'IOSFODNN7EXAMPLE'
            '-----BEGIN ' + 'RSA PRIVATE KEY-----'
        ) | Set-Content -LiteralPath $plantedFile -Encoding UTF8

        $finding = @(script:Get-SecretFinding -Path $TestDrive)

        $finding.Rule | Should -Contain 'AwsAccessKeyId'
        $finding.Rule | Should -Contain 'PrivateKeyBlock'
    }

    It 'finds no credential in the repository' {
        $scanRoot = @(
            'com.github.copilot/agents', 'instructions', 'skills', 'prompts', 'com.github.copilot/hooks', 'keybindings'
            'source', 'tests', 'reference', '.github', '.build', '.memory-bank'
        ) | ForEach-Object { Join-Path $script:repoRoot $_ }

        $scanRoot += @(
            Get-ChildItem -LiteralPath $script:repoRoot -File -Force |
                Select-Object -ExpandProperty FullName
        )

        # The scanner's own patterns are written out in full here.
        $finding = @(
            script:Get-SecretFinding -Path $scanRoot -ExcludeFile @($PSCommandPath)
        )

        $finding |
            ForEach-Object { '{0}:{1} matched {2}' -f $_.Path, $_.Line, $_.Rule } |
            Should -BeNullOrEmpty
    }
}
