<#
    .SYNOPSIS
        Ensures the built module manifest carries a UTF-8 byte-order mark.

    .DESCRIPTION
        Create_Changelog_Release_Output writes the changelog's release section
        into PrivateData.PSData.ReleaseNotes and saves the manifest without a
        byte-order mark. Windows PowerShell 5.1 decodes a BOM-less file with the
        system ANSI code page rather than UTF-8, so any non-ASCII character in
        the release notes -- an em dash, a curly quote, "EUR", section signs --
        is corrupted into multi-byte mojibake that breaks the manifest's
        restricted-language parser. Install-Module then fails with the generic
        "cannot be installed or updated because it is not a properly-formed
        module" error, hiding the real cause. Re-saving the manifest as UTF-8
        with a BOM fixes decoding on Windows PowerShell 5.1 without changing its
        content or behavior on any other host.
#>

[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '')]
param
(
    [Parameter()]
    [System.String]
    $ProjectName = (property ProjectName ''),

    [Parameter()]
    [System.String]
    $OutputDirectory = (property OutputDirectory (Join-Path -Path $BuildRoot -ChildPath 'output')),

    [Parameter()]
    [System.String]
    $BuiltModuleSubdirectory = (property BuiltModuleSubdirectory ''),

    [Parameter()]
    [System.String]
    $ModuleVersion = (property ModuleVersion ''),

    [Parameter()]
    [System.Management.Automation.SwitchParameter]
    $VersionedOutputDirectory = (property VersionedOutputDirectory $true),

    [Parameter()]
    [System.Collections.Hashtable]
    $BuildInfo = (property BuildInfo @{ })
)

task Repair_ManifestEncoding {
    . Set-SamplerTaskVariable

    $manifestPath = Join-Path -Path $BuiltModuleBase -ChildPath "$ProjectName.psd1"

    if (-not (Test-Path -LiteralPath $manifestPath))
    {
        throw "The built module manifest '$manifestPath' does not exist."
    }

    $bytes = [System.IO.File]::ReadAllBytes($manifestPath)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF

    if ($hasBom)
    {
        Write-Build -Color DarkGray -Text "`tManifest already carries a UTF-8 BOM: '$manifestPath'"
        return
    }

    Write-Build -Color DarkGray -Text "`tAdding a UTF-8 BOM so Windows PowerShell 5.1 decodes the manifest correctly: '$manifestPath'"

    $content = [System.Text.Encoding]::UTF8.GetString($bytes)
    $utf8Bom = [System.Text.UTF8Encoding]::new($true)
    [System.IO.File]::WriteAllText($manifestPath, $content, $utf8Bom)
}
