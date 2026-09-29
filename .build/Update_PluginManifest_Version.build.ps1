<#
    .SYNOPSIS
        Sets the plugin manifest to the release that the changelog pull request
        rolls over.

    .DESCRIPTION
        Create_ChangeLog_GitHub_PR (Sampler.GitHubTasks) moves the [Unreleased]
        changelog section under the full release tagged at the head of the main
        branch and commits the files listed in GitHubConfig.GitHubFilesToAdd.
        plugin.json must carry the version of the most recent released changelog
        section, so a rollover that commits only the changelog fails its own pull
        request; the v5.0.0 rollover did (CI run 36549550887).

        This task runs as the first job of Create_ChangeLog_GitHub_PR, so it is
        skipped whenever that task is. It resolves the same full release tag,
        rewrites only the manifest's version value, and enables rebase.autoStash
        in the local repository: the rollover pulls with rebase before it
        commits, and a rebase refuses a modified working tree.
#>

[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '')]
param
(
    [Parameter()]
    [System.String]
    $ProjectPath = (property ProjectPath $BuildRoot),

    [Parameter()]
    [System.String]
    $MainGitBranch = (property MainGitBranch 'main')
)

task Update_PluginManifest_Version -Before Create_ChangeLog_GitHub_PR {
    $manifestPath = Join-Path -Path $ProjectPath -ChildPath 'plugin.json'

    $mainHead = & git -C $ProjectPath rev-parse --verify --quiet "refs/remotes/origin/$MainGitBranch^{commit}"
    if ($LASTEXITCODE -ne 0 -or -not $mainHead)
    {
        Write-Build -Color Yellow -Text "`tNo origin/$MainGitBranch to read a release tag from; plugin.json is unchanged."
        return
    }

    # Sampler rolls the changelog over only for a full release tag at the head of main.
    $releaseTag = @(
        & git -C $ProjectPath tag --list --points-at $mainHead |
            Where-Object -FilterScript { $_ -cmatch '^v\d+\.\d+\.\d+$' }
    )
    if ($LASTEXITCODE -ne 0)
    {
        throw "Cannot list the tags at origin/$MainGitBranch to align plugin.json."
    }

    if ($releaseTag.Count -eq 0)
    {
        Write-Build -Color DarkGray -Text "`tNo full release tag at origin/$MainGitBranch; plugin.json is unchanged."
        return
    }

    if ($releaseTag.Count -gt 1)
    {
        throw "origin/$MainGitBranch carries more than one full release tag ($($releaseTag -join ', ')); plugin.json cannot follow both."
    }

    $releaseVersion = $releaseTag[0].Substring(1)

    $manifestBytes = [System.IO.File]::ReadAllBytes($manifestPath)
    $hasBom = $manifestBytes.Length -ge 3 -and $manifestBytes[0] -eq 0xEF -and $manifestBytes[1] -eq 0xBB -and $manifestBytes[2] -eq 0xBF
    $manifestText = [System.IO.File]::ReadAllText($manifestPath)

    try
    {
        $currentVersion = ($manifestText | ConvertFrom-Json -ErrorAction Stop).version
    }
    catch
    {
        throw "plugin.json is not valid JSON, so its version cannot be aligned with $($releaseTag[0]): $($_.Exception.Message)"
    }

    if ($currentVersion -isnot [System.String] -or [System.String]::IsNullOrEmpty($currentVersion))
    {
        throw 'plugin.json has no top-level version string to align with the release.'
    }

    if ($currentVersion -ceq $releaseVersion)
    {
        Write-Build -Color DarkGray -Text "`tplugin.json already carries $releaseVersion."
        return
    }

    # Rewrite the value in place: re-serializing would reformat the whole manifest.
    $versionPattern = '("version"\s*:\s*")' + [System.Text.RegularExpressions.Regex]::Escape($currentVersion) + '"'
    $versionMatch = [System.Text.RegularExpressions.Regex]::Matches($manifestText, $versionPattern)
    if ($versionMatch.Count -ne 1)
    {
        throw "plugin.json declares version $currentVersion $($versionMatch.Count) times, so the top-level value cannot be rewritten in place."
    }

    $match = $versionMatch[0]
    $updatedText = $manifestText.Substring(0, $match.Index) + $match.Groups[1].Value + $releaseVersion + '"' +
        $manifestText.Substring($match.Index + $match.Length)

    if (($updatedText | ConvertFrom-Json).version -cne $releaseVersion)
    {
        throw 'plugin.json declares its version somewhere other than the top level; it was not changed.'
    }

    & git -C $ProjectPath config --local rebase.autoStash true
    if ($LASTEXITCODE -ne 0)
    {
        throw 'Cannot enable rebase.autoStash, so the changelog rollover would refuse the updated plugin.json.'
    }

    [System.IO.File]::WriteAllText($manifestPath, $updatedText, [System.Text.UTF8Encoding]::new($hasBom))
    Write-Build -Color Green -Text "`tSet plugin.json to $releaseVersion for the $($releaseTag[0]) changelog rollover."
}
