[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '')]
param(
    [string] $TaskFilePath,
    [string] $ProjectPath,
    [string] $MainGitBranch,
    [bool] $RolloverEnabled,
    [string] $RecordPath
)

. $TaskFilePath

# Stands in for the Sampler.GitHubTasks task of the same name. It records the
# manifest version the rollover would commit, without a token or network access.
task Create_ChangeLog_GitHub_PR -If $RolloverEnabled {
    $manifestPath = Join-Path -Path $ProjectPath -ChildPath 'plugin.json'
    (Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json).version |
        Set-Content -LiteralPath $RecordPath
}

task . Create_ChangeLog_GitHub_PR
