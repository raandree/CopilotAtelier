# Custom Build Tasks

Extracted from `Skills/sampler-framework/SKILL.md` to keep the main skill body under Anthropic's 500-line budget.

## Contents

- Creating a Custom Task
- Task Files with Parameters
- Conditional Task Execution
- Registering Custom Tasks
- Inline Task Definition

Create custom InvokeBuild tasks in the `.build/` folder:

### Creating a Custom Task

```powershell
# .build/MyCustomTask.build.ps1
task MyCustomTask {
    Write-Build Green "Running custom task..."

    # Access build variables
    $moduleVersion = $script:ModuleVersion
    $outputDir = $script:OutputDirectory

    # Your custom logic here
    Write-Host "Building version $moduleVersion to $outputDir"
}
```

### Task Files with Parameters

For complex tasks, use a `param` block with InvokeBuild's `property` keyword to access build variables with defaults:

```powershell
# .build/MyAdvancedTask.build.ps1
param (
    [Parameter()]
    [System.String]
    $OutputDirectory = (property OutputDirectory (Join-Path $BuildRoot 'output')),

    [Parameter()]
    [System.String]
    $BuiltModuleSubdirectory = (property BuiltModuleSubdirectory ''),

    [Parameter()]
    [System.String]
    $ModuleVersion = (property ModuleVersion ''),

    [Parameter()]
    [System.Collections.Hashtable]
    $BuildInfo = (property BuildInfo @{ })
)

task MyAdvancedTask {
    # Initialize standard Sampler task variables (SourcePath, ProjectName, etc.)
    . Set-SamplerTaskVariable -AsNewBuild

    Write-Build DarkGray "`tOutput Directory = $OutputDirectory"
    Write-Build DarkGray "`tModule Version   = $ModuleVersion"

    # Task logic here
}
```

### Conditional Task Execution

Use the `-if` parameter to execute tasks only when conditions are met:

```powershell
# Only run on Windows PowerShell 5.1
task PowerShell5Compatibility -if ($PSVersionTable.PSEdition -eq 'Desktop') {
    # Remove modules incompatible with PS5.1
}

# Only run on PowerShell Core
task BuildGCPackages -if ($PSVersionTable.PSEdition -eq 'Core') {
    # Build Guest Configuration packages (requires PS7+)
}

# Only run when environment variables are set
task PublishPackages -if (
    $PSVersionTable.PSEdition -eq 'Core' -and ($env:azureClientSecret -or $env:azureIdToken)
) {
    # Publish with Azure credentials
}
```

### Registering Custom Tasks

Add the task to a workflow in `build.yaml`:

```yaml
BuildWorkflow:
  build:
    - Clean
    - MyCustomTask               # Custom task from .build/ folder
    - Build_Module_ModuleBuilder
    - Build_NestedModules_ModuleBuilder
    - Create_Changelog_Release_Output
```

### Inline Task Definition

For simple tasks, define them directly in `build.yaml`:

```yaml
BuildWorkflow:
  MyInlineTask: |
    {
        Write-Host "Running inline task"
    }

  build:
    - Clean
    - MyInlineTask
    - Build_Module_ModuleBuilder
```

---

