<#
.SYNOPSIS
    Configures VS Code settings for Copilot custom agents, instructions, skills, and prompts.
.DESCRIPTION
    Derives the folder name from the repository root (e.g. CopilotAtelier)
    and registers ~/<RepoName>/* as a file location so settings stay stable
    across machines with and without OneDrive.  When OneDrive is detected the
    script additionally registers ~/OneDrive/<RepoName>/* and creates those
    directories.  Creates the target subdirectories if they don't already exist.
    Idempotent: merges location entries instead of replacing them, strips JSONC
    comments before parsing, and creates a timestamped backup on every run.
#>

# --- Resolve the repo root and derive the folder name used for paths ---
$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$repoName = Split-Path -Leaf $repoRoot

$settingsPath = "$env:APPDATA\Code\User\settings.json"
$settingsDir  = Split-Path -Parent $settingsPath
$timestamp    = Get-Date -Format 'yyyyMMdd-HHmmss'

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
} elseif (Test-Path "$env:USERPROFILE\OneDrive") {
    $oneDriveRoot = "$env:USERPROFILE\OneDrive"
} else {
    $oneDriveRoot = $null
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

# --- Feature flags ---
$settings | Add-Member -NotePropertyName 'chat.includeApplyingInstructions' -NotePropertyValue $true -Force
$settings | Add-Member -NotePropertyName 'chat.includeReferencedInstructions' -NotePropertyValue $true -Force

# --- GitLens AI model ---
# Claude Opus 4.7 is GA in Copilot since April 16, 2026 and is the announced
# replacement for Opus 4.5 / 4.6. (Opus 4.6 Fast was retired April 10, 2026.)
$settings | Add-Member -NotePropertyName 'gitlens.ai.vscode.model' -NotePropertyValue 'copilot:claude-opus-4.7' -Force

# --- Copilot completions model ---
$settings | Add-Member -NotePropertyName 'github.copilot.advanced.model' -NotePropertyValue 'claude-opus-4.7' -Force

# --- Copilot chat enhancements ---
$settings | Add-Member -NotePropertyName 'github.copilot.chat.agent.thinkingTool' -NotePropertyValue $true -Force
$settings | Add-Member -NotePropertyName 'github.copilot.chat.search.semanticTextResults' -NotePropertyValue $true -Force

# --- Copilot request limits ---
$settings | Add-Member -NotePropertyName 'github.copilot.chat.agent.maxRequests' -NotePropertyValue 500 -Force

# --- Prompt-file discovery for VS Code Copilot Chat ---
# Unlike agents/instructions/skills, the chat extension does not auto-discover
# ~/.copilot/prompts as a well-known path - it only reads from the per-profile
# %APPDATA%\Code\User\prompts folder plus paths listed in this setting.
# Pointing it at the same junction the CLI uses keeps both surfaces in sync.
# Merge (do not overwrite) so any user-added prompt locations are preserved.
Merge-LocationSetting -Settings $settings -PropertyName 'chat.promptFilesLocations' -NewEntries @{
    '${userHome}/.copilot/prompts' = $true
}

# Write back
$settings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath -Encoding UTF8

# --- Clear and recreate the chosen target subdirectories, then copy files ---
# Only one location is populated: OneDrive when available, otherwise ~/<repoName>.
# A stale local copy from a previous run is removed when OneDrive is now used.
$subDirs = @('Agents', 'Instructions', 'Skills', 'Prompts')

if ($oneDriveRoot) {
    $targetBase = Join-Path $oneDriveRoot $repoName

    # Clean up legacy ~/<repoName> tree from earlier dual-copy runs.
    $legacyLocalBase = Join-Path $env:USERPROFILE $repoName
    if (Test-Path $legacyLocalBase) {
        Remove-Item -Path $legacyLocalBase -Recurse -Force
        Write-Host "Removed legacy local copy: $legacyLocalBase"
    }
} else {
    $targetBase = Join-Path $env:USERPROFILE $repoName
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
        Copy-Item -Path "$source\*" -Destination $dest -Recurse -Force
        Write-Host "Copied:  $source -> $dest"
    } else {
        Write-Host "Skipped: $source (not found in repo)"
    }
}

# --- Create ~/.copilot/{agents,instructions,skills,prompts} junctions ---
# Both the VS Code Copilot chat extension and the GitHub Copilot CLI discover
# customization files under $env:USERPROFILE\.copilot. Pointing those well-known
# folders at our single target tree (OneDrive or local fallback) keeps both
# clients in sync without writing chat.*FilesLocations settings.
#
# Behaviour for each link path:
#   - Already a junction/symlink -> remove and recreate at the current target.
#   - Real directory and empty   -> remove silently.
#   - Real directory, non-empty  -> prompt the user. On consent, copy contents
#     into the target (merge, no overwrite of newer files in the target) and
#     then remove. On refusal, skip the junction with a warning.
#   - Missing                    -> just create the junction.
$copilotRoot = Join-Path $env:USERPROFILE '.copilot'
if (-not (Test-Path $copilotRoot)) {
    New-Item -ItemType Directory -Path $copilotRoot -Force | Out-Null
    Write-Host "Created: $copilotRoot"
}

# Map repo subfolder (PascalCase) -> well-known .copilot link name (lowercase).
$junctionMap = [ordered]@{
    'Agents'       = 'agents'
    'Instructions' = 'instructions'
    'Skills'       = 'skills'
    'Prompts'      = 'prompts'
}

foreach ($entry in $junctionMap.GetEnumerator()) {
    $linkPath   = Join-Path $copilotRoot $entry.Value
    $targetPath = Join-Path $targetBase  $entry.Key

    if (-not (Test-Path $targetPath)) {
        Write-Host "Skipped junction: target missing - $targetPath"
        continue
    }

    if (Test-Path $linkPath) {
        $item = Get-Item -LiteralPath $linkPath -Force
        $isLink = $item.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)

        if ($isLink) {
            # Stale or correct junction: remove and recreate so it always
            # points at the current $targetPath.
            try {
                [IO.Directory]::Delete($linkPath)
            } catch {
                Remove-Item -LiteralPath $linkPath -Force -Recurse
            }
            Write-Host "Removed existing junction: $linkPath"
        } else {
            # Real directory. Check if it has any content.
            $children = Get-ChildItem -LiteralPath $linkPath -Force -ErrorAction SilentlyContinue
            if (-not $children) {
                Remove-Item -LiteralPath $linkPath -Force
                Write-Host "Removed empty directory: $linkPath"
            } else {
                Write-Host ""
                Write-Host "Directory '$linkPath' is not empty ($($children.Count) item(s))."
                Write-Host "It must be replaced with a junction to '$targetPath'."
                $answer = Read-Host 'Copy its contents into the target and then delete it? [y/N]'
                if ($answer -match '^(y|yes)$') {
                    # Merge into target without clobbering newer files already there.
                    foreach ($child in $children) {
                        $destChild = Join-Path $targetPath $child.Name
                        if (Test-Path -LiteralPath $destChild) {
                            Write-Host "  Skip (already present in target): $($child.Name)"
                            continue
                        }
                        Copy-Item -LiteralPath $child.FullName -Destination $destChild -Recurse -Force
                        Write-Host "  Copied: $($child.Name) -> $targetPath"
                    }
                    Remove-Item -LiteralPath $linkPath -Recurse -Force
                    Write-Host "Removed: $linkPath"
                } else {
                    Write-Host "Skipped junction: user declined to remove '$linkPath'."
                    continue
                }
            }
        }
    }

    New-Item -ItemType Junction -Path $linkPath -Target $targetPath | Out-Null
    Write-Host "Junction: $linkPath -> $targetPath"
}

# --- Set environment variable required by the GitHub Copilot CLI ---
# `gh copilot` consults COPILOT_ALLOW_ALL=1 to bypass the per-tool confirmation
# prompts that otherwise block non-interactive use of the custom agents and
# skills shipped from this repo. Persisted at User scope so every new shell
# session picks it up automatically; the current process variable is also set
# so the change is visible without opening a new shell.
$copilotEnvName  = 'COPILOT_ALLOW_ALL'
$copilotEnvValue = '1'
$existingValue   = [Environment]::GetEnvironmentVariable($copilotEnvName, 'User')
if ($existingValue -eq $copilotEnvValue) {
    Write-Host "Environment variable already set: $copilotEnvName=$copilotEnvValue (User)"
} else {
    [Environment]::SetEnvironmentVariable($copilotEnvName, $copilotEnvValue, 'User')
    Write-Host "Environment variable set: $copilotEnvName=$copilotEnvValue (User)"
    Write-Host "  Open a new shell to pick up the change in other sessions."
}
[Environment]::SetEnvironmentVariable($copilotEnvName, $copilotEnvValue, 'Process')

# --- Merge keybindings into %APPDATA%\Code\User\keybindings.json ---
# Idempotent: match on (key, command, when) tuple so re-runs do not duplicate
# entries and user-added bindings are preserved. Creates a timestamped backup
# before writing.
$keybindingsSource = Join-Path $repoRoot 'Keybindings\keybindings.json'
$keybindingsPath   = "$env:APPDATA\Code\User\keybindings.json"

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
