<#
.SYNOPSIS
    Configures VS Code settings for Copilot custom agents, instructions, skills, prompts, and hooks.
.DESCRIPTION
    Derives the folder name from the repository root (e.g. CopilotAtelier),
    copies customization files to OneDrive or the user profile, and links the
    well-known ~/.copilot directories to that target. Resolves the VS Code user
    directory using the conventions for Windows, macOS, and Linux. Idempotent:
    removes obsolete location aliases without disturbing user-defined entries,
    strips JSONC comments before parsing, and creates a timestamped backup on
    every run.
.PARAMETER SkipCopilotCliEnvironment
    Skips the user-scoped COPILOT_ALLOW_ALL configuration. Intended for
    sandboxed tests that must not mutate the host user profile.
.PARAMETER IncludeClaudeCodeLinks
    Additionally links ~/.claude/skills and ~/.agents/skills to the Skills
    directory so Claude Code and other agentskills.io clients discover the same
    library. Off by default: VS Code reads all three user-level skill locations,
    so enabling this registers every Skill more than once in VS Code. Use it on
    machines where a non-Copilot client is the primary consumer. Create-only:
    an existing path belongs to that tool and is left untouched.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [switch]$SkipCopilotCliEnvironment,

    [Parameter()]
    [switch]$IncludeClaudeCodeLinks
)

$ErrorActionPreference = 'Stop'

# --- Resolve the repo root and derive the folder name used for paths ---
$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$repoName = Split-Path -Leaf $repoRoot

$isWindowsPlatform = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
$isMacOSPlatform = $false
$isMacOSVariable = Get-Variable -Name IsMacOS -ErrorAction SilentlyContinue
if ($isMacOSVariable) {
    $isMacOSPlatform = [bool]$isMacOSVariable.Value
}

if ($isWindowsPlatform -and -not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
    $userHome = $env:USERPROFILE
} elseif (-not [string]::IsNullOrWhiteSpace($env:HOME)) {
    $userHome = $env:HOME
} else {
    $userHome = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
}

if ([string]::IsNullOrWhiteSpace($userHome)) {
    throw 'Unable to resolve the current user profile directory.'
}

if ($isWindowsPlatform) {
    $configRoot = $env:APPDATA
    if ([string]::IsNullOrWhiteSpace($configRoot)) {
        $configRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::ApplicationData)
    }
} elseif ($isMacOSPlatform) {
    $configRoot = Join-Path $userHome 'Library/Application Support'
} elseif (-not [string]::IsNullOrWhiteSpace($env:XDG_CONFIG_HOME)) {
    $configRoot = $env:XDG_CONFIG_HOME
} else {
    $configRoot = Join-Path $userHome '.config'
}

if ([string]::IsNullOrWhiteSpace($configRoot)) {
    throw 'Unable to resolve the VS Code configuration directory.'
}

$settingsDir = Join-Path (Join-Path $configRoot 'Code') 'User'
$settingsPath = Join-Path $settingsDir 'settings.json'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'

if (-not (Test-Path $settingsDir)) {
    New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
    Write-Host "Created VS Code User directory: $settingsDir"
}

if (-not (Test-Path $settingsPath)) {
    Write-Host "VS Code settings file not found at $settingsPath - creating a new one."
    '{}' | Set-Content -Path $settingsPath -Encoding UTF8
} else {
    # Back up the existing settings file with a timestamp
    $backupPath = "$settingsPath.$timestamp.bak"
    Copy-Item -Path $settingsPath -Destination $backupPath -Force
    Write-Host "Backup created: $backupPath"
}

# Helper: merge new keys into an existing location-map property without removing
# any paths the user added manually between runs.
function Merge-LocationSetting {
    param(
        [psobject]$Settings,
        [string]$PropertyName,
        [hashtable]$NewEntries
    )

    $merged = [ordered]@{}

    # Preserve every existing key
    if ($Settings.PSObject.Properties[$PropertyName]) {
        foreach ($prop in $Settings.$PropertyName.PSObject.Properties) {
            $merged[$prop.Name] = $prop.Value
        }
    }

    # Add / overwrite only the keys we care about
    foreach ($key in $NewEntries.Keys) {
        $merged[$key] = $NewEntries[$key]
    }

    $Settings | Add-Member -NotePropertyName $PropertyName `
        -NotePropertyValue ([pscustomobject]$merged) -Force
}

function Remove-LocationSettingEntry {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [psobject]$Settings,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$PropertyName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Entry
    )

    $property = $Settings.PSObject.Properties[$PropertyName]
    if (-not $property) {
        return
    }

    foreach ($entryName in $Entry) {
        if ($PSCmdlet.ShouldProcess($PropertyName, "Remove location entry '$entryName'")) {
            $property.Value.PSObject.Properties.Remove($entryName)
        }
    }

    if (@($property.Value.PSObject.Properties).Count -eq 0) {
        $Settings.PSObject.Properties.Remove($PropertyName)
    }
}

# Read and parse existing settings
$raw = Get-Content $settingsPath -Raw

# Strip JSONC single-line comments (// ...) that sit on their own line,
# block comments (/* ... */), and trailing commas before } or ]
$cleaned = $raw -replace '(?m)^\s*//.*$', ''
$cleaned = $cleaned -replace '/\*[\s\S]*?\*/', ''
$cleaned = $cleaned -replace ',(\s*[}\]])', '$1'
$settings = $cleaned | ConvertFrom-Json

# --- Detect OneDrive availability ---
# When both Consumer and Commercial are present, prompt the user to choose.
# Otherwise pick whichever is available.
$oneDriveCandidates = [ordered]@{}

if ($env:OneDriveConsumer -and (Test-Path $env:OneDriveConsumer)) {
    $oneDriveCandidates['Consumer'] = $env:OneDriveConsumer
}
if ($env:OneDriveCommercial -and (Test-Path $env:OneDriveCommercial)) {
    $oneDriveCandidates['Commercial'] = $env:OneDriveCommercial
}

if ($oneDriveCandidates.Count -gt 1) {
    Write-Host 'Multiple OneDrive accounts detected:'
    $index = 1
    $choices = @()
    foreach ($key in $oneDriveCandidates.Keys) {
        $choices += $key
        Write-Host "  [$index] $key - $($oneDriveCandidates[$key])"
        $index++
    }
    do {
        $selection = Read-Host "Select OneDrive account (1-$($choices.Count))"
    } while ($selection -notmatch '^\d+$' -or [int]$selection -lt 1 -or [int]$selection -gt $choices.Count)

    $selectedKey = $choices[[int]$selection - 1]
    $oneDriveRoot = $oneDriveCandidates[$selectedKey]
    Write-Host "Using OneDrive ($selectedKey): $oneDriveRoot"
} elseif ($oneDriveCandidates.Count -eq 1) {
    $oneDriveRoot = $oneDriveCandidates.Values | Select-Object -First 1
} elseif ($env:OneDrive -and (Test-Path $env:OneDrive)) {
    $oneDriveRoot = $env:OneDrive
} else {
    $defaultOneDrivePath = Join-Path $userHome 'OneDrive'
    if (Test-Path $defaultOneDrivePath) {
        $oneDriveRoot = $defaultOneDrivePath
    } else {
        $oneDriveRoot = $null
    }
}

# --- File location strategy ---
# Prefer OneDrive when available so a single synced copy serves every machine.
# Fall back to ~/<repoName> only when OneDrive is not installed. Discovery for
# agents, instructions, and skills is wired up later via NTFS junctions under
# $env:USERPROFILE\.copilot, which the VS Code Copilot chat extension and the
# GitHub Copilot CLI both auto-discover. Prompts are the exception: VS Code
# Copilot Chat reads them from %APPDATA%\Code\User\prompts plus any path in
# `chat.promptFilesLocations`, and does NOT auto-discover ~/.copilot/prompts
# (only the CLI does), so that single setting is still written below.
if ($oneDriveRoot) {
    Write-Host "OneDrive detected at: $oneDriveRoot - target tree will live there."
} else {
    Write-Host "OneDrive not found - target tree will live under ~/$repoName."
}

# Remove aliases written by setup versions that predate ~/.copilot discovery.
# Unrelated locations remain available to the user.
$legacyLocationMap = [ordered]@{
    'chat.agentFilesLocations' = 'Agents'
    'chat.instructionsFilesLocations' = 'Instructions'
    'chat.agentSkillsLocations' = 'Skills'
    'chat.promptFilesLocations' = 'Prompts'
}
foreach ($location in $legacyLocationMap.GetEnumerator()) {
    $legacyEntries = @(
        "~/$repoName/$($location.Value)"
        "~/OneDrive/$repoName/$($location.Value)"
    )
    $removeLocationSettingEntry = @{
        Settings = $settings
        PropertyName = $location.Key
        Entry = $legacyEntries
    }
    Remove-LocationSettingEntry @removeLocationSettingEntry
}

# --- Feature flags ---
$settings | Add-Member -NotePropertyName 'chat.includeApplyingInstructions' -NotePropertyValue $true -Force
$settings | Add-Member -NotePropertyName 'chat.includeReferencedInstructions' -NotePropertyValue $true -Force

# --- GitLens AI model ---
# Claude Opus 5 is the current Copilot release; Opus 4.8 remains GA as the
# fallback declared in every Agents/*.agent.md `model:` array.
$settings | Add-Member -NotePropertyName 'gitlens.ai.vscode.model' -NotePropertyValue 'copilot:claude-opus-5' -Force

# --- Retire the undocumented completions-model override ---
# `github.copilot.advanced` is the completions bag and has no documented `model`
# member, so earlier releases wrote a value Copilot never consumed. Remove the
# stale key instead of leaving misleading state in the user profile.
$settings.PSObject.Properties.Remove('github.copilot.advanced.model')

# --- Copilot chat enhancements ---
$settings | Add-Member -NotePropertyName 'github.copilot.chat.agent.thinkingTool' -NotePropertyValue $true -Force
$settings | Add-Member -NotePropertyName 'github.copilot.chat.search.semanticTextResults' -NotePropertyValue $true -Force

# --- Forked skill contexts ---
# Required by Skills that declare `context: fork` so their investigation runs in
# a dedicated subagent and only the result returns to the parent conversation.
$settings | Add-Member -NotePropertyName 'github.copilot.chat.skillTool.enabled' -NotePropertyValue $true -Force

# --- Copilot request limits ---
$settings | Add-Member -NotePropertyName 'github.copilot.chat.agent.maxRequests' -NotePropertyValue 500 -Force

# --- Prompt-file discovery for VS Code Copilot Chat ---
# Unlike agents/instructions/skills, the chat extension does not auto-discover
# ~/.copilot/prompts as a well-known path - it only reads from the per-profile
# %APPDATA%\Code\User\prompts folder plus paths listed in this setting.
# Pointing it at the same junction the CLI uses keeps both surfaces in sync.
# Merge (do not overwrite) so any user-added prompt locations are preserved.
Merge-LocationSetting -Settings $settings -PropertyName 'chat.promptFilesLocations' -NewEntries @{
    '~/.copilot/prompts' = $true
}

# --- Hook discovery ---
# ~/.copilot/hooks is a well-known user location, but naming it explicitly keeps
# discovery working if the implicit default changes, and leaves the Claude Code
# defaults untouched. Merge so user-added hook locations survive.
Merge-LocationSetting -Settings $settings -PropertyName 'chat.hookFilesLocations' -NewEntries @{
    '~/.copilot/hooks' = $true
}

# Write back
$settings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath -Encoding UTF8

# --- Clear and recreate the chosen target subdirectories, then copy files ---
# Only one location is populated: OneDrive when available, otherwise ~/<repoName>.
# A stale local copy from a previous run is removed when OneDrive is now used.
$subDirs = @('Agents', 'Instructions', 'Skills', 'Prompts', 'Hooks')

if ($oneDriveRoot) {
    $targetBase = Join-Path $oneDriveRoot $repoName

    # Clean up legacy ~/<repoName> tree from earlier dual-copy runs.
    $legacyLocalBase = Join-Path $userHome $repoName
    if (Test-Path $legacyLocalBase) {
        Remove-Item -Path $legacyLocalBase -Recurse -Force
        Write-Host "Removed legacy local copy: $legacyLocalBase"
    }
} else {
    $targetBase = Join-Path $userHome $repoName
}

foreach ($sub in $subDirs) {
    $dest = Join-Path $targetBase $sub
    if (Test-Path $dest) {
        Remove-Item -Path $dest -Recurse -Force
        Write-Host "Cleared: $dest"
    }
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    Write-Host "Created: $dest"

    $source = Join-Path $repoRoot $sub
    if (Test-Path $source) {
        $sourceContents = Join-Path $source '*'
        Copy-Item -Path $sourceContents -Destination $dest -Recurse -Force
        Write-Host "Copied:  $source -> $dest"
    } else {
        Write-Host "Skipped: $source (not found in repo)"
    }
}

# --- Create the Discovery links ---
# Both the VS Code Copilot chat extension and the GitHub Copilot CLI discover
# customization files under ~/.copilot. Pointing those well-known
# folders at our single target tree (OneDrive or local fallback) keeps both
# clients in sync without writing chat.*FilesLocations settings.
#
# Behaviour for each link path:
#   - Already a junction/symlink -> remove and recreate at the current target.
#   - Real directory and empty   -> remove silently.
#   - Real directory, non-empty  -> prompt the user. On consent, copy contents
#     into the target (merge, no overwrite of newer files in the target) and
#     then remove. On refusal, skip the junction with a warning.
#   - Missing                    -> just create the junction or symbolic link.
function Set-CustomizationLink {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$LinkPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$TargetPath,

        [Parameter(Mandatory)]
        [ValidateSet('Junction', 'SymbolicLink')]
        [string]$LinkItemType,

        # Third-party roots such as ~/.claude belong to another tool. Never
        # adopt, merge, or repoint anything already there.
        [Parameter()]
        [switch]$CreateOnly
    )

    if (-not (Test-Path -LiteralPath $TargetPath)) {
        Write-Host "Skipped link: target missing - $TargetPath"
        return
    }

    $linkParent = Split-Path -Parent $LinkPath
    if (-not (Test-Path -LiteralPath $linkParent)) {
        New-Item -ItemType Directory -Path $linkParent -Force | Out-Null
        Write-Host "Created: $linkParent"
    }

    if (Test-Path -LiteralPath $LinkPath) {
        if ($CreateOnly) {
            Write-Host "Skipped link: '$LinkPath' already exists and belongs to another tool."
            return
        }

        $item = Get-Item -LiteralPath $LinkPath -Force
        $isLink = $item.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)

        if ($isLink) {
            # Stale or correct link: remove and recreate so it always points at
            # the current $TargetPath. Never use -Recurse on a reparse point:
            # Windows PowerShell follows the link and deletes the target tree.
            if ($PSCmdlet.ShouldProcess($LinkPath, 'Remove existing link')) {
                try {
                    [IO.Directory]::Delete($LinkPath, $false)
                } catch {
                    Remove-Item -LiteralPath $LinkPath -Force
                }
                Write-Host "Removed existing link: $LinkPath"
            }
        } else {
            # Real directory. Check if it has any content.
            $children = Get-ChildItem -LiteralPath $LinkPath -Force -ErrorAction SilentlyContinue
            if (-not $children) {
                if ($PSCmdlet.ShouldProcess($LinkPath, 'Remove empty directory')) {
                    Remove-Item -LiteralPath $LinkPath -Force
                    Write-Host "Removed empty directory: $LinkPath"
                }
            } else {
                Write-Host ""
                Write-Host "Directory '$LinkPath' is not empty ($($children.Count) item(s))."
                Write-Host "It must be replaced with a link to '$TargetPath'."

                if (-not $PSCmdlet.ShouldProcess($LinkPath, "Merge into '$TargetPath' and remove")) {
                    return
                }

                $answer = Read-Host 'Copy its contents into the target and then delete it? [y/N]'
                if ($answer -match '^(y|yes)$') {
                    # Merge into target without clobbering files already there.
                    foreach ($child in $children) {
                        $destChild = Join-Path $TargetPath $child.Name
                        if (Test-Path -LiteralPath $destChild) {
                            Write-Host "  Skip (already present in target): $($child.Name)"
                            continue
                        }
                        Copy-Item -LiteralPath $child.FullName -Destination $destChild -Recurse -Force
                        Write-Host "  Copied: $($child.Name) -> $TargetPath"
                    }
                    Remove-Item -LiteralPath $LinkPath -Recurse -Force
                    Write-Host "Removed: $LinkPath"
                } else {
                    Write-Host "Skipped link: user declined to remove '$LinkPath'."
                    return
                }
            }
        }
    }

    if ($PSCmdlet.ShouldProcess($LinkPath, "Create $LinkItemType to '$TargetPath'")) {
        New-Item -ItemType $LinkItemType -Path $LinkPath -Target $TargetPath | Out-Null
        Write-Host "${LinkItemType}: $LinkPath -> $TargetPath"
    }
}

$copilotRoot = Join-Path $userHome '.copilot'
$linkItemType = if ($isWindowsPlatform) { 'Junction' } else { 'SymbolicLink' }

# Repo subfolder (PascalCase) -> well-known Discovery link path (lowercase).
$linkPlan = [ordered]@{
    (Join-Path $copilotRoot 'agents') = 'Agents'
    (Join-Path $copilotRoot 'instructions') = 'Instructions'
    (Join-Path $copilotRoot 'skills') = 'Skills'
    (Join-Path $copilotRoot 'prompts') = 'Prompts'
    (Join-Path $copilotRoot 'hooks') = 'Hooks'
}

foreach ($entry in $linkPlan.GetEnumerator()) {
    $setCustomizationLink = @{
        LinkPath = $entry.Key
        TargetPath = Join-Path $targetBase $entry.Value
        LinkItemType = $linkItemType
    }
    Set-CustomizationLink @setCustomizationLink
}

# Opt-in only, and create-only. VS Code reads ~/.copilot/skills,
# ~/.claude/skills, and ~/.agents/skills, so these links register every Skill
# more than once in VS Code. They exist for machines where Claude Code or
# another agentskills.io client is the primary consumer. An existing path is
# left untouched: it belongs to that tool, and adopting it would move the
# user's own skills into a tree the next setup run rebuilds from the repository.
if ($IncludeClaudeCodeLinks) {
    Write-Host 'Claude Code links requested: VS Code will register Skills from more than one location.'

    $claudeCodeLink = @(
        Join-Path (Join-Path $userHome '.claude') 'skills'
        Join-Path (Join-Path $userHome '.agents') 'skills'
    )

    foreach ($linkPath in $claudeCodeLink) {
        $setCustomizationLink = @{
            LinkPath = $linkPath
            TargetPath = Join-Path $targetBase 'Skills'
            LinkItemType = $linkItemType
            CreateOnly = $true
        }
        Set-CustomizationLink @setCustomizationLink
    }
}

# --- Set environment variable required by the GitHub Copilot CLI ---
# `gh copilot` consults COPILOT_ALLOW_ALL=1 to bypass the per-tool confirmation
# prompts that otherwise block non-interactive use of the custom agents and
# skills shipped from this repo. Persisted at User scope so every new shell
# session picks it up automatically; the current process variable is also set
# so the change is visible without opening a new shell.
$copilotEnvName = 'COPILOT_ALLOW_ALL'
$copilotEnvValue = '1'
if ($SkipCopilotCliEnvironment) {
    Write-Verbose "Skipped environment variable: $copilotEnvName (requested)"
} else {
    $existingValue = [Environment]::GetEnvironmentVariable($copilotEnvName, 'User')
    if ($existingValue -eq $copilotEnvValue) {
        Write-Host "Environment variable already set: $copilotEnvName=$copilotEnvValue (User)"
    } else {
        [Environment]::SetEnvironmentVariable($copilotEnvName, $copilotEnvValue, 'User')
        Write-Host "Environment variable set: $copilotEnvName=$copilotEnvValue (User)"
        Write-Host "  Open a new shell to pick up the change in other sessions."
    }
    [Environment]::SetEnvironmentVariable($copilotEnvName, $copilotEnvValue, 'Process')
}

# --- Merge keybindings into %APPDATA%\Code\User\keybindings.json ---
# Idempotent: match on (key, command, when) tuple so re-runs do not duplicate
# entries and user-added bindings are preserved. Creates a timestamped backup
# before writing.
$keybindingsSource = Join-Path (Join-Path $repoRoot 'Keybindings') 'keybindings.json'
$keybindingsPath = Join-Path $settingsDir 'keybindings.json'

if (Test-Path $keybindingsSource) {
    if (-not (Test-Path $keybindingsPath)) {
        Write-Host "VS Code keybindings file not found at $keybindingsPath - creating a new one."
        '[]' | Set-Content -Path $keybindingsPath -Encoding UTF8
    } else {
        $kbBackup = "$keybindingsPath.$timestamp.bak"
        Copy-Item -Path $keybindingsPath -Destination $kbBackup -Force
        Write-Host "Backup created: $kbBackup"
    }

    # Parse existing bindings (JSONC-tolerant: strip // and /* */ comments and trailing commas)
    $kbRaw     = Get-Content $keybindingsPath -Raw
    $kbCleaned = $kbRaw -replace '(?m)^\s*//.*$', ''
    $kbCleaned = $kbCleaned -replace '/\*[\s\S]*?\*/', ''
    $kbCleaned = $kbCleaned -replace ',(\s*[}\]])', '$1'
    if ([string]::IsNullOrWhiteSpace($kbCleaned)) { $kbCleaned = '[]' }
    $existingBindings = @($kbCleaned | ConvertFrom-Json)

    # Parse desired bindings from the repo
    $desiredRaw     = Get-Content $keybindingsSource -Raw
    $desiredCleaned = $desiredRaw -replace '(?m)^\s*//.*$', ''
    $desiredCleaned = $desiredCleaned -replace '/\*[\s\S]*?\*/', ''
    $desiredCleaned = $desiredCleaned -replace ',(\s*[}\]])', '$1'
    $desiredBindings = @($desiredCleaned | ConvertFrom-Json)

    # Build a tuple key for deduplication
    function Get-BindingKey {
        param($Binding)
        $k = if ($Binding.PSObject.Properties['key'])     { [string]$Binding.key }     else { '' }
        $c = if ($Binding.PSObject.Properties['command']) { [string]$Binding.command } else { '' }
        $w = if ($Binding.PSObject.Properties['when'])    { [string]$Binding.when }    else { '' }
        "$k|$c|$w"
    }

    $desiredKeys = @{}
    foreach ($b in $desiredBindings) { $desiredKeys[(Get-BindingKey $b)] = $true }

    # Keep every existing binding that is not one of ours, then append ours.
    # This removes stale copies of our bindings (e.g. after we update the "when"
    # clause) and avoids duplicates.
    $kept = @($existingBindings | Where-Object { -not $desiredKeys.ContainsKey((Get-BindingKey $_)) })
    $merged = @($kept) + @($desiredBindings)

    $merged | ConvertTo-Json -Depth 10 | Set-Content $keybindingsPath -Encoding UTF8
    Write-Host "Keybindings merged: $($desiredBindings.Count) bindings from repo, $($kept.Count) user bindings preserved."
} else {
    Write-Host "Skipped keybindings merge: $keybindingsSource not found."
}

Write-Host "`nSettings updated at: $settingsPath"
Write-Host "Restart VS Code to apply changes."
