# VSCode Integration

Extracted from `Skills/sampler-framework/SKILL.md` to keep the main skill body under Anthropic's 500-line budget.

## Contents

- Setting Up the Environment
- .vscode/settings.json
- .vscode/analyzersettings.psd1
- .vscode/tasks.json
- Additional VSCode Settings for DSC Projects

### Setting Up the Environment

Do not run `build.ps1 -Tasks noop` in the PowerShell Extension host. Tests and
builds use the detached wrapper. For interactive inspection of already-built
artifacts, configure the current session explicitly:

```powershell
$separator = [IO.Path]::PathSeparator
$moduleRoots = @(
    (Join-Path $PWD 'output')
    (Join-Path $PWD 'output/RequiredModules')
    $env:PSModulePath
)
$env:PSModulePath = $moduleRoots -join $separator
```

This mirrors the useful path setup without invoking a build in the current
session.

### .vscode/settings.json

```json
{
    "powershell.codeFormatting.autoCorrectAliases": true,
    "powershell.codeFormatting.useCorrectCasing": true,
    "powershell.codeFormatting.pipelineIndentationStyle": "IncreaseIndentationForFirstPipeline",
    "powershell.codeFormatting.openBraceOnSameLine": true,
    "powershell.codeFormatting.newLineAfterOpenBrace": true,
    "powershell.codeFormatting.newLineAfterCloseBrace": true,
    "powershell.codeFormatting.whitespaceBeforeOpenBrace": true,
    "powershell.codeFormatting.whitespaceBeforeOpenParen": true,
    "powershell.codeFormatting.whitespaceAroundOperator": true,
    "powershell.codeFormatting.whitespaceAfterSeparator": true,
    "powershell.codeFormatting.whitespaceBetweenParameters": false,
    "powershell.scriptAnalysis.settingsPath": ".vscode/analyzersettings.psd1",
    "files.trimTrailingWhitespace": true,
    "files.insertFinalNewline": true,
    "files.associations": {
        "*.ps1xml": "xml"
    }
}
```

### .vscode/analyzersettings.psd1

```powershell
@{
    CustomRulePath      = @(
        './output/RequiredModules/Indented.ScriptAnalyzerRules'
    )
    IncludeDefaultRules = $true
    IncludeRules        = @(
        # Default rules from PSScriptAnalyzer
        'PSAvoidDefaultValueForMandatoryParameter'
        'PSAvoidDefaultValueSwitchParameter'
        'PSAvoidGlobalAliases'
        'PSAvoidGlobalFunctions'
        'PSAvoidGlobalVars'
        'PSAvoidInvokingEmptyMembers'
        'PSAvoidUsingCmdletAliases'
        'PSAvoidUsingComputerNameHardcoded'
        'PSAvoidUsingPlainTextForPassword'
        'PSAvoidUsingWMICmdlet'
        'PSMissingModuleManifestField'
        'PSProvideCommentHelp'
        'PSUseApprovedVerbs'
        'PSUseShouldProcessForStateChangingFunctions'
        'PSUseSingularNouns'

        # Custom rules
        'Measure-*'
    )
}
```

#### DSC-Specific Analyzer Rules

DSC projects should use `DscResource.AnalyzerRules` instead of (or alongside) `Indented.ScriptAnalyzerRules`:

```powershell
@{
    CustomRulePath      = '.\output\RequiredModules\DscResource.AnalyzerRules'
    includeDefaultRules = $true
    IncludeRules        = @(
        # Standard PSScriptAnalyzer rules
        'PSAvoidDefaultValueForMandatoryParameter'
        'PSAvoidUsingCmdletAliases'
        'PSAvoidUsingEmptyCatchBlock'
        'PSAvoidUsingInvokeExpression'
        'PSAvoidUsingPositionalParameters'
        'PSAvoidUsingWriteHost'
        'PSMissingModuleManifestField'
        'PSProvideCommentHelp'
        'PSUseApprovedVerbs'
        'PSUseCmdletCorrectly'
        'PSUseOutputTypeCorrectly'
        'PSAvoidGlobalVars'
        'PSAvoidUsingConvertToSecureStringWithPlainText'
        'PSUseDeclaredVarsMoreThanAssignments'
        'PSUsePSCredentialType'

        # DSC-specific rules
        'PSDSCReturnCorrectTypesForDSCFunctions'
        'PSDSCStandardDSCFunctionsInResource'
        'PSDSCUseIdenticalMandatoryParametersForDSC'
        'PSDSCUseIdenticalParametersForDSC'
        'PSDSCUseVerboseMessageInDSCResource'

        # Custom Measure-* rules from DscResource.AnalyzerRules
        'Measure-*'
    )
}
```

### .vscode/tasks.json

Create `.vscode/Start-DetachedBuild.ps1` from this project-local wrapper. It
returns immediately with unique process, log, and result metadata:

```powershell
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('default', 'build', 'test')]
    [string]$Workflow,

    [ValidateNotNullOrEmpty()]
    [string]$LauncherPath = (Join-Path $HOME (
        '.copilot/skills/long-running-job-monitor/scripts/Start-DetachedPowerShell.ps1'
    ))
)

$buildCommand = switch ($Workflow) {
    'default' { '.\build.ps1' }
    'build'   { '.\build.ps1 -Tasks build' }
    'test'    { '.\build.ps1 -AutoRestore -Tasks test' }
}
$runId = [guid]::NewGuid().ToString('N')
$logPath = Join-Path $env:TEMP "sampler-$Workflow-$runId.log"
$workingDirectory = (Split-Path $PSScriptRoot -Parent).Replace("'", "''")
$escapedLogPath = $logPath.Replace("'", "''")
$payload = @"
Set-Location -LiteralPath '$workingDirectory'
`$ErrorActionPreference = 'Stop'
try {
    & {
        $buildCommand
    } *>&1 | Out-File -LiteralPath '$escapedLogPath' -Encoding utf8
}
catch {
    `$_ | Format-List * -Force | Out-String |
        Out-File -LiteralPath '$escapedLogPath' -Encoding utf8 -Append
    throw
}
"@
$encodedPayload = [Convert]::ToBase64String(
    [Text.Encoding]::Unicode.GetBytes($payload)
)
if (-not (Test-Path -LiteralPath $LauncherPath -PathType Leaf)) {
    throw "Detached launcher not found: $LauncherPath"
}
$launch = & $LauncherPath -EncodedCommand $encodedPayload

[pscustomobject]@{
    ProcessId = $launch.ProcessId
    LogPath   = $logPath
    Platform  = $launch.Platform
    ResultPath = $launch.ResultPath
}
```

Then define tasks that run only the wrapper. Do not attach `build.ps1` directly
to a shell task; detached output lives in the returned log, so terminal problem
matchers do not apply to the launcher task.

On a later status check, read `ResultPath`: `0` is success, `1` is failure, and
an absent file means no completion result is available yet.

```jsonc
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "build",
            "type": "process",
            "command": "pwsh",
            "args": [
                "-NoProfile",
                "-NonInteractive",
                "-File",
                "${workspaceFolder}/.vscode/Start-DetachedBuild.ps1",
                "-Workflow",
                "build"
            ],
            "presentation": {
                "echo": true,
                "reveal": "always",
                "panel": "new"
            },
            "problemMatcher": []
        },
        {
            "label": "test",
            "type": "process",
            "command": "pwsh",
            "args": [
                "-NoProfile",
                "-NonInteractive",
                "-File",
                "${workspaceFolder}/.vscode/Start-DetachedBuild.ps1",
                "-Workflow",
                "test"
            ],
            "presentation": {
                "echo": true,
                "reveal": "always",
                "panel": "dedicated"
            },
            "problemMatcher": []
        }
    ]
}
```

### Additional VSCode Settings for DSC Projects

DSC projects benefit from additional settings for the bundled modules path and spelling dictionary:

```json
{
    "powershell.developer.bundledModulesPath": "${cwd}/output/RequiredModules",
    "powershell.codeFormatting.preset": "Custom",
    "powershell.codeFormatting.alignPropertyValuePairs": true,
    "files.trimFinalNewlines": true,
    "[markdown]": {
        "files.trimTrailingWhitespace": false,
        "files.encoding": "utf8"
    },
    "cSpell.words": [
        "gitversion",
        "keepachangelog",
        "pscmdlet",
        "steppable"
    ]
}
```

---

