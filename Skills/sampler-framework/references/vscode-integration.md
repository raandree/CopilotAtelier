# VSCode Integration

Extracted from `Skills/sampler-framework/SKILL.md` to keep the main skill body under Anthropic's 500-line budget.

## Contents

- Setting Up the Environment
- .vscode/settings.json
- .vscode/analyzersettings.psd1
- .vscode/tasks.json
- Additional VSCode Settings for DSC Projects

### Setting Up the Environment

Before running or debugging tests in VSCode, ensure the session is configured:

```powershell
# In the PowerShell Integrated Console:
./build.ps1 -Tasks noop
```

This bootstraps the environment without building or testing. The `noop` task only runs the bootstrap and sets up `$env:PSModulePath`.

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

Define build and test tasks with problem matchers for Pester test failures:

```jsonc
{
    "version": "2.0.0",
    "_runner": "terminal",
    "windows": {
        "options": {
            "shell": {
                "executable": "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe",
                "args": ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command"]
            }
        }
    },
    "linux": {
        "options": {
            "shell": {
                "executable": "/usr/bin/pwsh",
                "args": ["-NoProfile", "-Command"]
            }
        }
    },
    "tasks": [
        {
            "label": "build",
            "type": "shell",
            "command": "&${cwd}/build.ps1",
            "args": [],
            "presentation": {
                "echo": true,
                "reveal": "always",
                "focus": true,
                "panel": "new",
                "clear": false
            },
            "problemMatcher": [
                {
                    "owner": "powershell",
                    "fileLocation": ["absolute"],
                    "severity": "error",
                    "pattern": [
                        {
                            "regexp": "^\\s*(\\[-\\]\\s*.*?)(\\d+)ms\\s*$",
                            "message": 1
                        },
                        { "regexp": "(.*)", "code": 1 },
                        { "regexp": "" },
                        {
                            "regexp": "^.*,\\s*(.*):\\s*line\\s*(\\d+).*",
                            "file": 1,
                            "line": 2
                        }
                    ]
                }
            ]
        },
        {
            "label": "test",
            "type": "shell",
            "command": "&${cwd}/build.ps1",
            "args": ["-AutoRestore", "-Tasks", "test"],
            "presentation": {
                "echo": true,
                "reveal": "always",
                "focus": true,
                "panel": "dedicated"
            },
            "problemMatcher": [
                {
                    "owner": "powershell",
                    "fileLocation": ["absolute"],
                    "severity": "error",
                    "pattern": [
                        {
                            "regexp": "^\\s*(\\[-\\]\\s*.*?)(\\d+)ms\\s*$",
                            "message": 1
                        },
                        { "regexp": "(.*)", "code": 1 },
                        { "regexp": "" },
                        {
                            "regexp": "^.*,\\s*(.*):\\s*line\\s*(\\d+).*",
                            "file": 1,
                            "line": 2
                        }
                    ]
                }
            ]
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

