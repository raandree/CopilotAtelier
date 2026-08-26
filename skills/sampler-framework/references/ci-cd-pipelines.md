# CI/CD Integration

Extracted from `Skills/sampler-framework/SKILL.md` to keep the main skill body under Anthropic's 500-line budget.

## Contents

- Azure Pipelines (azure-pipelines.yml)
- GitHub Actions (.github/workflows/ci.yml)
- Azure Pipelines to GitHub Actions translation
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

### GitHub Actions (.github/workflows/ci.yml)

The same three stages, expressed as three jobs. Copy this verbatim and change
only the module name in the step summary, the `github.repository_owner` value,
and the test matrix. Divergence between repositories is the thing this template
exists to prevent.

```yaml
# Continuous integration pipeline for <ModuleName>.
#
#   * Build  - calculate the version with GitVersion, build and package the
#              module, then publish the output/ folder as a build artifact.
#   * Test   - on every target platform, reuse the build artifact and run the
#              Sampler test workflow.
#   * Deploy - on the upstream repository, for pushes to main or v* tags,
#              publish the release to GitHub and the PowerShell Gallery and
#              raise the changelog pull request.
#
# Required repository secrets (Settings > Secrets and variables > Actions):
#   GitHubToken     - personal access token used to create the GitHub release
#                     and the changelog pull request.
#   GalleryApiToken - PowerShell Gallery API key used to publish the module.
name: CI

# Azure DevOps renames each run to the GitVersion number via
# ##vso[build.updatebuildnumber]. GitHub Actions has no equivalent: run-name is
# evaluated before any job starts and can only see the github/inputs contexts,
# so it cannot contain a version GitVersion computes mid-run. The closest we can
# get is: show the version in the run title for tag releases (the tag IS the
# version), and stamp the computed GitVersion value into the test/deploy job
# names and the build job summary on every run (see the build job's outputs).
run-name: ${{ github.ref_type == 'tag' && format('Release {0}', github.ref_name) || '' }}

on:
  push:
    branches:
      - main
    tags:
      - 'v*'
      - '!v*-*'
    paths-ignore:
      - CHANGELOG.md
  pull_request:
    branches:
      - main
  workflow_dispatch:

permissions:
  contents: read

env:
  buildArtifactName: output
  defaultBranch: main

jobs:
  build:
    name: Package Module
    runs-on: ubuntu-latest
    # Expose the GitVersion value to downstream jobs so they can show it in their
    # display names - the closest GitHub gets to Azure DevOps' run renaming.
    outputs:
      fullSemVer: ${{ steps.gitversion.outputs.FullSemVer }}
      nuGetVersion: ${{ steps.gitversion.outputs.NuGetVersionV2 }}
    steps:
      - name: Checkout
        uses: actions/checkout@v7
        with:
          # GitVersion needs the full history to calculate the version.
          fetch-depth: 0

      - name: Calculate ModuleVersion (GitVersion)
        id: gitversion
        shell: pwsh
        env:
          # GitVersion 5.x targets an older .NET; allow it to run on the
          # runner's newer shared framework.
          DOTNET_ROLL_FORWARD: LatestMajor
        run: |
          dotnet tool install --global GitVersion.Tool --version 5.*
          $env:PATH += [System.IO.Path]::PathSeparator + (Join-Path -Path $HOME -ChildPath '.dotnet/tools')
          $gitVersionObject = dotnet-gitversion | ConvertFrom-Json
          $gitVersionObject.PSObject.Properties.ForEach{
              Write-Host -Object "Setting output '$($_.Name)' with value '$($_.Value)'."
              "$($_.Name)=$($_.Value)" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
          }
          Write-Host -Object "ModuleVersion (FullSemVer): $($gitVersionObject.FullSemVer)"
          "## <ModuleName> $($gitVersionObject.FullSemVer)" | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8

      - name: Build & Package Module
        shell: pwsh
        env:
          ModuleVersion: ${{ steps.gitversion.outputs.NuGetVersionV2 }}
        run: ./build.ps1 -ResolveDependency -Tasks pack

      - name: Publish Build Artifact
        uses: actions/upload-artifact@v7
        with:
          name: ${{ env.buildArtifactName }}
          path: output/
          if-no-files-found: error
          retention-days: 7

  test:
    name: Test ${{ needs.build.outputs.fullSemVer }} (${{ matrix.os }})
    needs: build
    runs-on: ${{ matrix.os }}
    strategy:
      fail-fast: false
      matrix:
        os:
          - ubuntu-latest
          - windows-latest
          - macos-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v7
        with:
          fetch-depth: 0

      - name: Download Build Artifact
        uses: actions/download-artifact@v8
        with:
          name: ${{ env.buildArtifactName }}
          path: output/

      - name: Run Tests
        shell: pwsh
        run: ./build.ps1 -Tasks test

      - name: Publish Test Results
        if: always()
        uses: actions/upload-artifact@v7
        with:
          name: CodeCoverage-${{ matrix.os }}
          path: output/testResults/
          if-no-files-found: warn

  deploy:
    name: Deploy Module ${{ needs.build.outputs.fullSemVer }}
    needs: [build, test]
    runs-on: ubuntu-latest
    # Only deploy from the upstream repository, for pushes to the default
    # branch or for version tags.
    if: >-
      github.repository_owner == '<your-org-name>' &&
      (github.ref == 'refs/heads/main' || startsWith(github.ref, 'refs/tags/'))
    permissions:
      contents: write
      pull-requests: write
    steps:
      - name: Checkout
        uses: actions/checkout@v7
        with:
          fetch-depth: 0

      - name: Download Build Artifact
        uses: actions/download-artifact@v8
        with:
          name: ${{ env.buildArtifactName }}
          path: output/

      - name: Publish Release
        shell: pwsh
        env:
          GitHubToken: ${{ secrets.GitHubToken }}
          GalleryApiToken: ${{ secrets.GalleryApiToken }}
          ModuleVersion: ${{ needs.build.outputs.nuGetVersion }}
          ReleaseBranch: ${{ env.defaultBranch }}
          MainGitBranch: ${{ env.defaultBranch }}
        run: ./build.ps1 -Tasks publish

      - name: Send Changelog PR
        shell: pwsh
        env:
          GitHubToken: ${{ secrets.GitHubToken }}
          ReleaseBranch: ${{ env.defaultBranch }}
          MainGitBranch: ${{ env.defaultBranch }}
        run: ./build.ps1 -Tasks Create_ChangeLog_GitHub_PR
```

#### Testing a second PowerShell edition

Azure DevOps switches edition with `pwsh: true|false`. GitHub Actions has no
per-task equivalent, so a matrix that varies the shell must set it through
`jobs.<job_id>.defaults.run` — a step's `shell` key accepts **no** context, and
`shell: ${{ matrix.shell }}` on a step fails the whole workflow file at compile
time with "Unrecognized named-value". Give each leg a separate artifact key too,
because two legs on `windows-latest` would otherwise collide on the same
artifact name.

```yaml
  test:
    name: Test ${{ needs.build.outputs.fullSemVer }} (${{ matrix.name }})
    needs: build
    runs-on: ${{ matrix.os }}
    strategy:
      fail-fast: false
      matrix:
        include:
          - name: ubuntu-latest
            artifact: ubuntu-latest
            os: ubuntu-latest
            shell: pwsh
            arguments: '-Tasks test'
          - name: windows-latest (PowerShell 7)
            artifact: windows-latest-pwsh
            os: windows-latest
            shell: pwsh
            arguments: '-Tasks test'
          - name: windows-latest (Windows PowerShell 5.1)
            artifact: windows-latest-powershell
            os: windows-latest
            shell: powershell
            arguments: '-Tasks test'

    # A step's `shell` key does not accept the matrix context; `defaults.run` is
    # the only place that does.
    defaults:
      run:
        shell: ${{ matrix.shell }}

    steps:
      # ... checkout and download as above ...
      - name: Run Tests
        run: ./build.ps1 ${{ matrix.arguments }}
```

Restrict a platform's scope with `-PesterTag` in `arguments` when part of the
suite is platform-bound; tag the portable tests deliberately, because the
restricted leg selects by tag.

#### Action versions

Bump all three actions together and in every repository at once, or the
templates drift. Do not assume the majors move in step — as of 2026-07 the
current majors are `checkout@v7`, `upload-artifact@v7`, and
`download-artifact@v8`, and the major that first stopped defaulting to the
deprecated Node 20 runtime differs per action:

| Action | First Node 24 default | Current major | Breaking change that matters |
|---|---|---|---|
| `actions/checkout` | v5 | v7 | v7 blocks fork-PR checkout under `pull_request_target` and `workflow_run`; harmless for a `push` / `pull_request` pipeline |
| `actions/upload-artifact` | v6 | v7 | v7 adds opt-in `archive: false` direct uploads; defaults unchanged |
| `actions/download-artifact` | v7 | v8 | v5 changed the output path for single downloads **by ID** only — downloading by `name` is unaffected; v8 makes a digest mismatch an error instead of a warning |

### Azure Pipelines to GitHub Actions translation

| Azure Pipelines | GitHub Actions | Note |
|---|---|---|
| `Agent.Source.Git.ShallowFetchDepth: 0` | `actions/checkout` with `fetch-depth: 0` | Required in **every** job that runs git, not just the build |
| `##vso[task.setvariable variable=X]` | `"X=value" >> $env:GITHUB_OUTPUT` plus `jobs.<id>.outputs` | Step needs an `id`; a downstream job needs `needs:` |
| `##vso[build.updatebuildnumber]` | No equivalent | `run-name` cannot see a mid-run value; use job names plus `$GITHUB_STEP_SUMMARY` |
| `pwsh: true` / `pwsh: false` | `shell: pwsh` / `shell: powershell` | Literal only; a matrix-driven shell goes in `defaults.run` |
| `contains(System.TeamFoundationCollectionUri, 'org')` | `github.repository_owner == 'org'` | Blocks fork deployment; PR refs are `refs/pull/N/merge`, so a ref check already excludes pull requests |
| `paths: exclude: CHANGELOG.md` | `paths-ignore: [CHANGELOG.md]` | Stops the release commit retriggering the pipeline |
| `PublishTestResults@2` | `actions/upload-artifact@v4` | Actions has no native NUnit renderer; upload `output/testResults/` |
| `$(GitHubToken)` | `${{ secrets.GitHubToken }}` | Not `secrets.GITHUB_TOKEN` — the automatic token cannot raise the changelog PR |
| implicit `dependsOn` chain | `needs:` | Deploy needs `[build, test]` |

Two extras Actions requires that Azure Pipelines does not: `permissions:
contents: write` and `pull-requests: write` on the deploy job, and
`DOTNET_ROLL_FORWARD: LatestMajor` so GitVersion 5.x runs on the runner's newer
shared .NET framework.

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

