# CI/CD Integration

Extracted from `Skills/sampler-framework/SKILL.md` to keep the main skill body under Anthropic's 500-line budget.

## Contents

- Azure Pipelines (azure-pipelines.yml)
- Critical CI/CD Configuration
- Required Pipeline Variables (Secrets)

### Azure Pipelines (azure-pipelines.yml)

A standard three-stage pipeline:

```yaml
trigger:
  branches:
    include:
      - main
  paths:
    exclude:
      - CHANGELOG.md
  tags:
    include:
      - "v*"
    exclude:
      - "*-*"

variables:
  buildFolderName: output
  buildArtifactName: output
  testResultFolderName: testResults
  defaultBranch: main
  Agent.Source.Git.ShallowFetchDepth: 0   # REQUIRED for GitVersion

stages:
  #---------------------------------------------------------------------------
  # Stage 1: Build
  #---------------------------------------------------------------------------
  - stage: Build
    jobs:
      - job: Package_Module
        displayName: 'Package Module'
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          - pwsh: |
              dotnet tool install --global GitVersion.Tool --version 5.*
              $gitVersionObject = dotnet-gitversion | ConvertFrom-Json
              $gitVersionObject.PSObject.Properties.ForEach{
                  Write-Host "Setting Task Variable '$($_.Name)' with value '$($_.Value)'."
                  Write-Host "##vso[task.setvariable variable=$($_.Name);]$($_.Value)"
              }
              Write-Host "##vso[build.updatebuildnumber]$($gitVersionObject.FullSemVer)"
            displayName: Calculate ModuleVersion (GitVersion)

          - task: PowerShell@2
            name: package
            displayName: 'Build & Package Module'
            inputs:
              filePath: './build.ps1'
              arguments: '-ResolveDependency -tasks pack'
              pwsh: true
            env:
              ModuleVersion: $(NuGetVersionV2)

          - task: PublishPipelineArtifact@1
            displayName: 'Publish Build Artifact'
            inputs:
              targetPath: '$(buildFolderName)/'
              artifact: $(buildArtifactName)
              publishLocation: 'pipeline'
              parallel: true

  #---------------------------------------------------------------------------
  # Stage 2: Test (multiple editions)
  #---------------------------------------------------------------------------
  - stage: Test
    dependsOn: Build
    jobs:
      - job: test_windows_ps7
        displayName: 'Windows (PowerShell 7)'
        pool:
          vmImage: 'windows-latest'
        steps:
          - task: DownloadPipelineArtifact@2
            displayName: 'Download Build Artifact'
            inputs:
              buildType: 'current'
              artifactName: $(buildArtifactName)
              targetPath: '$(Build.SourcesDirectory)/$(buildFolderName)'

          - task: PowerShell@2
            name: test
            displayName: 'Run Tests'
            inputs:
              filePath: './build.ps1'
              arguments: '-tasks test'
              pwsh: true            # PowerShell 7

          - task: PublishTestResults@2
            displayName: 'Publish Test Results'
            condition: succeededOrFailed()
            inputs:
              testResultsFormat: 'NUnit'
              testResultsFiles: '$(buildFolderName)/$(testResultFolderName)/NUnit*.xml'
              testRunTitle: 'Windows (PS7)'

      - job: test_windows_ps51
        displayName: 'Windows (PowerShell 5.1)'
        pool:
          vmImage: 'windows-latest'
        steps:
          - task: DownloadPipelineArtifact@2
            displayName: 'Download Build Artifact'
            inputs:
              buildType: 'current'
              artifactName: $(buildArtifactName)
              targetPath: '$(Build.SourcesDirectory)/$(buildFolderName)'

          - task: PowerShell@2
            name: test
            displayName: 'Run Tests'
            inputs:
              filePath: './build.ps1'
              arguments: '-tasks test'
              pwsh: false           # Windows PowerShell 5.1

          - task: PublishTestResults@2
            displayName: 'Publish Test Results'
            condition: succeededOrFailed()
            inputs:
              testResultsFormat: 'NUnit'
              testResultsFiles: '$(buildFolderName)/$(testResultFolderName)/NUnit*.xml'
              testRunTitle: 'Windows (PS5.1)'

  #---------------------------------------------------------------------------
  # Stage 3: Deploy
  #---------------------------------------------------------------------------
  - stage: Deploy
    dependsOn: Test
    condition: |
      and(
        succeeded(),
        or(
          eq(variables['Build.SourceBranch'], 'refs/heads/main'),
          startsWith(variables['Build.SourceBranch'], 'refs/tags/')
        ),
        contains(variables['System.TeamFoundationCollectionUri'], '<your-org-name>')
      )
    jobs:
      - job: Deploy_Module
        displayName: 'Deploy Module'
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          - task: DownloadPipelineArtifact@2
            displayName: 'Download Build Artifact'
            inputs:
              buildType: 'current'
              artifactName: $(buildArtifactName)
              targetPath: '$(Build.SourcesDirectory)/$(buildFolderName)'

          - task: PowerShell@2
            name: publishRelease
            displayName: 'Publish Release'
            inputs:
              filePath: './build.ps1'
              arguments: '-tasks publish'
              pwsh: true
            env:
              GitHubToken: $(GitHubToken)
              GalleryApiToken: $(GalleryApiToken)
              ReleaseBranch: $(defaultBranch)
              MainGitBranch: $(defaultBranch)

          - task: PowerShell@2
            name: sendChangelogPR
            displayName: 'Send Changelog PR'
            inputs:
              filePath: './build.ps1'
              arguments: '-tasks Create_ChangeLog_GitHub_PR'
              pwsh: true
            env:
              GitHubToken: $(GitHubToken)
              ReleaseBranch: $(defaultBranch)
              MainGitBranch: $(defaultBranch)
```

### Critical CI/CD Configuration

| Setting | Value | Why |
|---|---|---|
| `Agent.Source.Git.ShallowFetchDepth` | `0` | GitVersion needs full git history |
| `pwsh: true` | PowerShell 7 | Cross-platform, modern features |
| `pwsh: false` | Windows PowerShell 5.1 | Test backward compatibility |
| Deploy `condition` | Include org name | Prevent fork deployments |
| `ReleaseBranch` / `MainGitBranch` | `main` | Must match default branch |

### Required Pipeline Variables (Secrets)

| Variable | Purpose |
|---|---|
| `GitHubToken` | GitHub personal access token for releases and PRs |
| `GalleryApiToken` | PowerShell Gallery API key for publishing |

---

