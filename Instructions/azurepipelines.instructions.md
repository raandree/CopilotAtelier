---
applyTo: "**/azure-pipelines.yml,**/azure-pipelines*.yml,**/.azuredevops/*.yml"
---

# Azure Pipelines Best Practices and Standards

## Pipeline Structure

### Top-Level Schema

```yaml
---
trigger:
  branches:
    include:
      - main
      - release/*

pr:
  branches:
    include:
      - main

pool:
  vmImage: 'windows-latest'

variables:
  - name: buildConfiguration
    value: 'Release'

stages:
  - stage: Build
    displayName: 'Build & Test'
    jobs:
      - job: BuildJob
        steps:
          - task: PowerShell@2
            displayName: 'Run build'
            inputs:
              targetType: 'inline'
              script: |
                .\build.ps1 -ResolveDependency -Tasks build
```

### Key Hierarchy

```
trigger / pr / schedules
  → pool
    → variables
      → stages
        → jobs
          → steps
            → task / script / powershell / bash
```

Always organize the YAML in this order for consistency and readability.

## Triggers

### Branch Triggers

```yaml
# Include specific branches (recommended)
trigger:
  branches:
    include:
      - main
      - release/*
    exclude:
      - feature/experimental-*

# Path filters
trigger:
  branches:
    include:
      - main
  paths:
    include:
      - source/**
      - tests/**
    exclude:
      - '**/*.md'
      - docs/**
```

### PR Triggers

```yaml
pr:
  branches:
    include:
      - main
      - develop
  paths:
    exclude:
      - '**/*.md'
      - docs/**
  drafts: false  # Don't trigger on draft PRs
```

### Scheduled Triggers

```yaml
schedules:
  - cron: '0 3 * * 1-5'  # 3 AM UTC, weekdays
    displayName: 'Nightly build'
    branches:
      include:
        - main
    always: false  # Only run if there are changes
```

### Disable Triggers

```yaml
# Disable CI trigger (manual only)
trigger: none

# Disable PR trigger
pr: none
```

## Stages, Jobs, and Steps

### Stages

Use stages to separate logical phases of the pipeline:

```yaml
stages:
  - stage: Build
    displayName: 'Build'
    jobs:
      - job: BuildModule
        steps:
          - script: echo "Building..."

  - stage: Test
    displayName: 'Test'
    dependsOn: Build
    jobs:
      - job: RunTests
        steps:
          - script: echo "Testing..."

  - stage: Deploy
    displayName: 'Deploy'
    dependsOn: Test
    condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/main'))
    jobs:
      - deployment: DeployToGallery
        environment: 'PSGallery'
        strategy:
          runOnce:
            deploy:
              steps:
                - script: echo "Deploying..."
```

### Jobs

```yaml
jobs:
  - job: Build
    displayName: 'Build Module'
    timeoutInMinutes: 30
    cancelTimeoutInMinutes: 5
    pool:
      vmImage: 'windows-latest'
    steps:
      - checkout: self
        fetchDepth: 0  # Full history for GitVersion
      - task: PowerShell@2
        displayName: 'Build'
        inputs:
          targetType: 'inline'
          script: .\build.ps1 -ResolveDependency -Tasks build
```

### Matrix Strategy

Test across multiple platforms and PowerShell versions:

```yaml
jobs:
  - job: Test
    displayName: 'Test on'
    strategy:
      matrix:
        Windows_PS51:
          vmImage: 'windows-latest'
          pwshVersion: '5.1'
          usePowerShell: true
        Windows_PS73:
          vmImage: 'windows-latest'
          pwshVersion: '7.3'
          usePowerShell: false
        Ubuntu_PS73:
          vmImage: 'ubuntu-latest'
          pwshVersion: '7.3'
          usePowerShell: false
    pool:
      vmImage: $(vmImage)
    steps:
      - task: PowerShell@2
        displayName: 'Run tests'
        inputs:
          targetType: 'inline'
          script: .\build.ps1 -Tasks test
          pwsh: ${{ ne(variables.usePowerShell, 'true') }}
```

## Steps and Tasks

### PowerShell Tasks

```yaml
# Inline script
- task: PowerShell@2
  displayName: 'Run build script'
  inputs:
    targetType: 'inline'
    script: |
      .\build.ps1 -ResolveDependency -Tasks build
    pwsh: true               # Use PowerShell 7 (false = Windows PowerShell 5.1)
    errorActionPreference: 'stop'
    failOnStderr: false       # PowerShell writes progress to stderr

# File-based script
- task: PowerShell@2
  displayName: 'Run deployment script'
  inputs:
    targetType: 'filePath'
    filePath: './scripts/Deploy.ps1'
    arguments: '-Environment Production -Verbose'
    pwsh: true
```

### Script Shorthand

```yaml
# PowerShell shorthand
- pwsh: |
    Write-Host "Running on PowerShell $($PSVersionTable.PSVersion)"
  displayName: 'PowerShell 7 script'

# Windows PowerShell shorthand
- powershell: |
    Write-Host "Running on Windows PowerShell"
  displayName: 'Windows PowerShell script'

# Bash shorthand
- bash: echo "Hello from bash"
  displayName: 'Bash script'
```

### Display Names

- **ALWAYS** set `displayName` on every step, job, and stage
- Use descriptive names that explain the purpose, not the command
- Use sentence case: `'Run Pester tests'` not `'run pester tests'`

```yaml
# Good
- task: PowerShell@2
  displayName: 'Build module with ModuleBuilder'

# Bad — no display name (shows task type in UI)
- task: PowerShell@2
  inputs:
    script: .\build.ps1
```

## Variables

### Variable Declaration

```yaml
# Simple variables
variables:
  buildConfiguration: 'Release'
  moduleName: 'MyModule'

# Structured variables (allows mixing with groups and templates)
variables:
  - name: buildConfiguration
    value: 'Release'
  - name: moduleName
    value: 'MyModule'
  - group: 'PSGallery-Credentials'
  - template: variables/common.yml
```

### Variable Groups

Use variable groups for shared configuration and secrets:

```yaml
variables:
  - group: 'PSGallery-Credentials'    # Contains NuGetApiKey
  - group: 'Azure-ServicePrincipal'   # Contains Azure credentials
```

### Secret Variables

- **NEVER** log or echo secret variables
- Use `$(secretVar)` syntax — Azure Pipelines masks them in logs
- Define secrets in variable groups linked to Azure Key Vault when possible

```yaml
# BAD — exposes secret in log
- script: echo $(NuGetApiKey)

# GOOD — use as parameter, never echo
- task: PowerShell@2
  displayName: 'Publish module'
  inputs:
    targetType: 'inline'
    script: |
      Publish-Module -Path ./output/builtModule/$(moduleName) `
        -NuGetApiKey $env:NUGET_API_KEY `
        -Repository PSGallery
  env:
    NUGET_API_KEY: $(NuGetApiKey)
```

### Predefined Variables

Commonly used predefined variables:

| Variable | Description | Example Value |
|---|---|---|
| `Build.SourceBranch` | Full ref of the triggering branch | `refs/heads/main` |
| `Build.SourceBranchName` | Short branch name | `main` |
| `Build.BuildId` | Unique build ID | `12345` |
| `Build.BuildNumber` | Build number (configurable) | `20260226.1` |
| `Build.Repository.LocalPath` | Local checkout path | `D:\a\1\s` |
| `Build.ArtifactStagingDirectory` | Staging path for artifacts | `D:\a\1\a` |
| `System.PullRequest.PullRequestId` | PR number (PR builds only) | `42` |
| `Agent.OS` | Agent operating system | `Windows_NT` |

## Templates

### Step Templates

```yaml
# templates/build-steps.yml
parameters:
  - name: tasks
    type: string
    default: 'build'
  - name: resolveDependency
    type: boolean
    default: false

steps:
  - checkout: self
    fetchDepth: 0

  - task: PowerShell@2
    displayName: 'Run build (${{ parameters.tasks }})'
    inputs:
      targetType: 'inline'
      script: |
        $params = @{ Tasks = '${{ parameters.tasks }}' }
        if ('${{ parameters.resolveDependency }}' -eq 'True') {
            $params.ResolveDependency = $true
        }
        .\build.ps1 @params
      pwsh: true
```

### Using Templates

```yaml
stages:
  - stage: Build
    jobs:
      - job: BuildModule
        steps:
          - template: templates/build-steps.yml
            parameters:
              tasks: 'build'
              resolveDependency: true

  - stage: Test
    dependsOn: Build
    jobs:
      - job: TestModule
        steps:
          - template: templates/build-steps.yml
            parameters:
              tasks: 'test'
```

### Variable Templates

```yaml
# templates/variables/common.yml
variables:
  moduleName: 'MyModule'
  buildConfiguration: 'Release'
  psGalleryFeed: 'PSGallery'
```

## Artifacts

### Publishing Artifacts

```yaml
- task: PublishPipelineArtifact@1
  displayName: 'Publish built module'
  inputs:
    targetPath: '$(Build.SourcesDirectory)/output/builtModule'
    artifact: 'builtModule'
    publishLocation: 'pipeline'

- task: PublishPipelineArtifact@1
  displayName: 'Publish test results'
  condition: always()  # Publish even on failure
  inputs:
    targetPath: '$(Build.SourcesDirectory)/output/testResults'
    artifact: 'testResults'
    publishLocation: 'pipeline'
```

### Downloading Artifacts

```yaml
- task: DownloadPipelineArtifact@2
  displayName: 'Download built module'
  inputs:
    artifact: 'builtModule'
    path: '$(Pipeline.Workspace)/builtModule'
```

### Test Results Publishing

```yaml
- task: PublishTestResults@2
  displayName: 'Publish test results'
  condition: always()
  inputs:
    testResultsFormat: 'NUnit'
    testResultsFiles: '**/output/testResults/NUnitXml_*.xml'
    failTaskOnFailedTests: true

- task: PublishCodeCoverageResults@2
  displayName: 'Publish code coverage'
  condition: always()
  inputs:
    summaryFileLocation: '**/output/testResults/CodeCov_*.xml'
```

## Sampler Pipeline Pattern

### Complete Sampler Pipeline

```yaml
---
trigger:
  branches:
    include:
      - main
  tags:
    include:
      - 'v*'

pr:
  branches:
    include:
      - main

variables:
  - name: buildFolderName
    value: 'output'
  - name: buildArtifactName
    value: 'output'
  - name: testArtifactName
    value: 'testResults'

stages:
  - stage: Build
    displayName: 'Build'
    jobs:
      - job: BuildModule
        displayName: 'Build module'
        pool:
          vmImage: 'windows-latest'
        steps:
          - checkout: self
            fetchDepth: 0

          - task: PowerShell@2
            displayName: 'Build module'
            inputs:
              targetType: 'inline'
              script: .\build.ps1 -ResolveDependency -Tasks build
              pwsh: true

          - task: PublishPipelineArtifact@1
            displayName: 'Publish build output'
            inputs:
              targetPath: '$(buildFolderName)/'
              artifact: '$(buildArtifactName)'

  - stage: Test
    displayName: 'Test'
    dependsOn: Build
    jobs:
      - job: TestWindows
        displayName: 'Test on Windows'
        pool:
          vmImage: 'windows-latest'
        steps:
          - checkout: self
            fetchDepth: 0

          - task: DownloadPipelineArtifact@2
            displayName: 'Download build output'
            inputs:
              artifact: '$(buildArtifactName)'
              path: '$(buildFolderName)/'

          - task: PowerShell@2
            displayName: 'Run tests'
            inputs:
              targetType: 'inline'
              script: .\build.ps1 -Tasks test
              pwsh: true

          - task: PublishTestResults@2
            displayName: 'Publish test results'
            condition: always()
            inputs:
              testResultsFormat: 'NUnit'
              testResultsFiles: '$(buildFolderName)/testResults/NUnitXml_*.xml'

          - task: PublishPipelineArtifact@1
            displayName: 'Publish test artifacts'
            condition: always()
            inputs:
              targetPath: '$(buildFolderName)/testResults/'
              artifact: '$(testArtifactName)'

  - stage: Deploy
    displayName: 'Deploy to PSGallery'
    dependsOn: Test
    condition: |
      and(
        succeeded(),
        startsWith(variables['Build.SourceBranch'], 'refs/tags/v')
      )
    jobs:
      - deployment: PublishModule
        displayName: 'Publish to PSGallery'
        environment: 'PSGallery'
        pool:
          vmImage: 'windows-latest'
        strategy:
          runOnce:
            deploy:
              steps:
                - task: DownloadPipelineArtifact@2
                  displayName: 'Download build output'
                  inputs:
                    artifact: '$(buildArtifactName)'
                    path: '$(Pipeline.Workspace)/$(buildArtifactName)'

                - task: PowerShell@2
                  displayName: 'Publish module'
                  inputs:
                    targetType: 'inline'
                    script: .\build.ps1 -Tasks publish
                    pwsh: true
                  env:
                    GalleryApiToken: $(NuGetApiKey)
```

## Conditions

### Common Conditions

```yaml
# Run only on main branch
condition: eq(variables['Build.SourceBranch'], 'refs/heads/main')

# Run only on tag push
condition: startsWith(variables['Build.SourceBranch'], 'refs/tags/v')

# Run on PR builds only
condition: eq(variables['Build.Reason'], 'PullRequest')

# Run even if previous stage/job failed
condition: always()

# Run only if previous stage succeeded
condition: succeeded()

# Combine conditions
condition: |
  and(
    succeeded(),
    eq(variables['Build.SourceBranch'], 'refs/heads/main'),
    ne(variables['Build.Reason'], 'PullRequest')
  )
```

## Environments and Approvals

### Deployment Jobs

Use `deployment` jobs with `environment` for production deployments:

```yaml
jobs:
  - deployment: DeployProduction
    displayName: 'Deploy to Production'
    environment: 'Production'  # Configure approvals in Azure DevOps UI
    strategy:
      runOnce:
        deploy:
          steps:
            - script: echo "Deploying..."
```

### Environment Gates

Configure approval gates in the Azure DevOps UI:
1. Go to **Pipelines** → **Environments**
2. Select the environment
3. Add **Approvals and checks**:
   - Required reviewers
   - Business hours
   - Branch control

## Security Best Practices

### Least Privilege

- Use service connections with minimal permissions
- Scope variable groups to specific pipelines
- Use `checkout: self` with `persistCredentials: false` when Git push is not needed

### Secret Management

- Store secrets in Azure Key Vault linked variable groups
- Never hardcode secrets in pipeline YAML
- Use `env:` mapping to pass secrets to scripts as environment variables
- Secrets are automatically masked in logs

### Pipeline Permissions

- Restrict who can edit pipeline YAML (branch policies)
- Use `extends` templates from a protected repo for enforced patterns
- Enable **Protect access to repositories in YAML pipelines** in project settings

## Performance

### Caching

```yaml
- task: Cache@2
  displayName: 'Cache RequiredModules'
  inputs:
    key: 'modules | "$(Agent.OS)" | RequiredModules.psd1'
    restoreKeys: |
      modules | "$(Agent.OS)"
    path: '$(Build.SourcesDirectory)/output/RequiredModules'
```

### Parallel Jobs

- Use `dependsOn: []` for jobs that can run in parallel
- Use matrix strategy for cross-platform testing
- Keep stages sequential only when there are true dependencies

### Checkout Optimization

```yaml
- checkout: self
  fetchDepth: 0     # Full history (needed for GitVersion)
  clean: true       # Clean workspace
  lfs: false        # Disable LFS if not needed
```

Use `fetchDepth: 1` (shallow clone) when full history is not needed (saves time for large repos).

## Common Anti-Patterns

### Running Build Without Display Names

Every step should have a `displayName`. Without it, the pipeline log shows generic task names that are hard to navigate.

### Ignoring Exit Codes

```yaml
# BAD — continues even if build fails
- script: .\build.ps1 -Tasks test
  displayName: 'Run tests'

# GOOD — PowerShell task handles errors properly
- task: PowerShell@2
  displayName: 'Run tests'
  inputs:
    targetType: 'inline'
    script: .\build.ps1 -Tasks test
    pwsh: true
    errorActionPreference: 'stop'
```

### Hardcoding Agent Paths

```yaml
# BAD — hardcoded path
- script: cd D:\a\1\s && .\build.ps1

# GOOD — use predefined variables
- script: cd $(Build.SourcesDirectory) && .\build.ps1
```

### Not Publishing Results on Failure

```yaml
# BAD — test results lost on failure
- task: PublishTestResults@2
  inputs:
    testResultsFiles: '**/testResults/*.xml'

# GOOD — publish even on failure
- task: PublishTestResults@2
  condition: always()
  inputs:
    testResultsFiles: '**/testResults/*.xml'
```
