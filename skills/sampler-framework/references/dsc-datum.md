# DSC and Datum Configuration Data Projects

Extracted from `Skills/sampler-framework/SKILL.md` to keep the main skill body under Anthropic's 500-line budget.

## Contents

- DSC Project Structure
- Datum Resolution Hierarchy (Datum.yml)
- Node Definition Files
- Role Definition Files
- DSC Build Configuration (build.yaml)
- DSC-Specific ModuleBuildTasks
- DSC-Specific Pester and HQRM Configuration
- Sampler.DscPipeline Configuration
- SetPSModulePath for DSC Isolation
- DSC RequiredModules.psd1
- DSC-Specific Build Output
- DSC Testing Categories
- DSC CI/CD Pipeline Variants
- DSC Custom Build Task Patterns
- TaskHeader Formatting
- PullRequestConfig for Azure DevOps

Sampler is not limited to standard PowerShell module builds. Projects like [DscWorkshop](https://github.com/dsccommunity/DscWorkshop) use Sampler to compile DSC configuration data via [Datum](https://github.com/gaelcolas/Datum) into MOF artifacts, producing an end-to-end release pipeline for infrastructure-as-code.

### DSC Project Structure

A Datum-based DSC project differs significantly from a standard module project:

```text
MyDscProject/
├── .build/                          # Custom build tasks
│   ├── ConvertMofFilesToUnicode.ps1
│   ├── GuestConfigurationTasks.ps1
│   └── PowerShell5Compatibility.ps1
├── .vscode/
│   ├── analyzersettings.psd1
│   ├── settings.json
│   └── tasks.json
├── source/
│   ├── AllNodes/                    # Per-node configuration data (YAML)
│   │   ├── Dev/
│   │   │   ├── DSCFile01.yml
│   │   │   └── DSCWeb01.yml
│   │   ├── Prod/
│   │   └── Test/
│   ├── Baselines/                   # Baseline configuration layers
│   │   ├── DscLcm.yml
│   │   ├── Security.yml
│   │   └── Server.yml
│   ├── Datum.yml                    # Datum resolution precedence definition
│   ├── Domains/                     # Domain-specific data
│   ├── Environment/                 # Shared environment defaults
│   ├── Environments/                # Per-environment overrides
│   ├── Global/                      # Global settings (shared across all)
│   ├── Locations/                   # Location-specific data
│   ├── Roles/                       # Role definitions (WebServer, FileServer, etc.)
│   │   ├── DomainController.yml
│   │   ├── FileServer.yml
│   │   └── WebServer.yml
│   ├── MyDscProject.psd1           # Module manifest (composite resources)
│   └── MyDscProject.psm1           # Root module (may be empty)
├── tests/
│   ├── Acceptance/                  # Post-build MOF verification
│   │   └── TestMofFiles.Tests.ps1
│   ├── ConfigData/                  # Configuration data validation
│   │   ├── ConfigData.Tests.ps1
│   │   └── CompositeResources.Tests.ps1
│   ├── QA/                          # Module quality assurance
│   │   └── module.tests.ps1
│   └── ReferenceFiles/             # Reference RSOP comparison
│       └── TestReferenceFiles.Tests.ps1
├── build.ps1
├── build.yaml
├── RequiredModules.psd1
├── Resolve-Dependency.ps1
├── Resolve-Dependency.psd1
├── GitVersion.yml
├── CHANGELOG.md
├── azure-pipelines.yml
├── azure-pipelines On-Prem.yml     # On-premises variant
└── azure-pipelines Guest Configuration.yml
```

### Datum Resolution Hierarchy (Datum.yml)

Datum merges configuration data from multiple layers using a precedence order. The `Datum.yml` file defines the resolution order and merge behavior:

```yaml
ResolutionPrecedence:
  - AllNodes\$($Node.Environment)\$($Node.NodeName)
  - Environment\$($Node.Environment)
  - Locations\$($Node.Location)
  - Roles\$($Node.Role)
  - Baselines\Security
  - Baselines\$($Node.Baseline)
  - Baselines\DscLcm

DatumHandlersThrowOnError: true
DatumHandlers:
  Datum.ProtectedData::ProtectedDatum:
    CommandOptions:
      PlainTextPassword: SomeSecret
  Datum.InvokeCommand::InvokeCommand:
    SkipDuringLoad: true

DscLocalConfigurationManagerKeyName: LcmConfig

default_lookup_options: MostSpecific

lookup_options:
  Configurations:
    merge_basetype_array: Unique
  Baseline:
    merge_hash: deep
  WindowsFeatures:
    merge_hash: deep
  WindowsFeatures\Names:
    merge_basetype_array: Unique
  RegistryValues:
    merge_hash: deep
  RegistryValues\Values:
    merge_hash_array: UniqueKeyValTuples
    merge_options:
      tuple_keys:
        - Key
```

### Node Definition Files

Each node (server/machine) gets a YAML file under `source/AllNodes/<Environment>/`:

```yaml
# source/AllNodes/Dev/DSCWeb01.yml
NodeName: '[x={ $Node.Name }=]'
Environment: '[x={ $File.Directory.BaseName } =]'
Role: WebServer
Description: '[x= "$($Node.Role) in $($Node.Environment)" =]'
Location: Singapore
Baseline: Server

ComputerSettings:
  Name: '[x={ $Node.NodeName }=]'
  Description: '[x= "$($Node.Role) in $($Node.Environment)" =]'

NetworkIpConfiguration:
  Interfaces:
    - InterfaceAlias: DscWorkshop 0
      IpAddress: 192.168.111.101

PSDscAllowPlainTextPassword: True
PSDscAllowDomainUser: True

LcmConfig:
  ConfigurationRepositoryWeb:
    Server:
      ConfigurationNames: '[x={ $Node.NodeName }=]'

DscTagging:
  Layers:
    - '[x={ Get-DatumSourceFile -Path $File } =]'
  NodeVersion: '[x={ $datum.Baselines.DscLcm.DscTagging.Version } =]'
  NodeRole: '[x={ $Node.Role } =]'
```

### Role Definition Files

Roles define which DSC configurations apply and their parameters:

```yaml
# source/Roles/WebServer.yml
Configurations:
  - WindowsServices
  - RegistryValues
  - FileSystemObjects
  - WebApplicationPools
  - WebApplications

FileSystemObjects:
  Items:
    - DestinationPath: C:\Inetpub\TestApp1
      Type: Directory
    - DestinationPath: C:\Inetpub\TestApp1\default.html
      Type: File
      Contents: This is TestApp1
      DependsOn: '[FileSystemObject]FileSystemObject_C__Inetpub_TestApp1'

WebApplicationPools:
  Items:
    - Name: TestAppPool1
      Ensure: Present
      IdentityType: ApplicationPoolIdentity
      State: Started
  DependsOn:
    - '[FileSystemObjects]FileSystemObjects'
    - '[WindowsFeatures]WindowsFeatures'
```

### DSC Build Configuration (build.yaml)

A DSC project's `build.yaml` differs from a standard module project in several key ways:

```yaml
---
BuiltModuleSubDirectory: Module

BuildWorkflow:
  '.':
    - build
    - pack
    - test

  build:
    - Clean
    - PowerShell5Compatibility       # Remove PS7-only modules on PS5.1
    - Build_Module_ModuleBuilder
    - LoadDatumConfigData            # Load Datum hierarchy
    - TestConfigData                 # Validate config data integrity
    - CompileDatumRsop               # Compile Resultant Set of Policy
    - TestReferenceRsop              # Compare RSOP against references
    - Set_PSModulePath               # Isolate module path
    - TestDscResources               # Validate DSC resources exist
    - CompileRootConfiguration       # Compile MOF files
    - CompileRootMetaMof             # Compile Meta MOF files

  pack:
    - PowerShell5Compatibility
    - LoadDatumConfigData
    - ConvertMofFilesToUnicode       # Fix MOF encoding
    - NewMofChecksums                # Generate checksums
    - CompressModulesWithChecksum    # Package DSC resources
    - Compress_Artifact_Collections  # Package build artifacts
    - TestBuildAcceptance            # Verify artifacts were created

  packguestconfiguration:           # Azure Guest Configuration packages
    - PowerShell5Compatibility
    - LoadDatumConfigData
    - NewMofChecksums
    - CompressModulesWithChecksum
    - Compress_Artifact_Collections
    - TestBuildAcceptance
    - build_guestconfiguration_packages_from_MOF
    - publish_guestconfiguration_packages

  rsop:                             # Quick RSOP-only workflow
    - LoadDatumConfigData
    - CompileDatumRsop
    - TestDscResources

  hqrmtest:                         # High Quality Resource Module tests
    - Invoke_HQRM_Tests_Stop_On_Fail

  publish:
    - publish_module_to_gallery
    - Publish_Release_To_GitHub
    - Create_ChangeLog_GitHub_PR
```

### DSC-Specific ModuleBuildTasks

DSC projects import tasks from additional modules beyond the standard `Sampler` and `Sampler.GitHubTasks`:

```yaml
ModuleBuildTasks:
  Sampler:
    - '*.build.Sampler.ib.tasks'      # Core build tasks
  Sampler.DscPipeline:
    - '*.ib.tasks'                    # DSC pipeline tasks (LoadDatumConfigData,
                                      #   CompileDatumRsop, CompileRootConfiguration, etc.)
  Sampler.GitHubTasks:
    - '*.ib.tasks'                    # GitHub release/changelog tasks
  Sampler.AzureDevOpsTasks:
    - 'Task.*'                        # Azure DevOps integration tasks
  DscResource.DocGenerator:
    - 'Task.*'                        # DSC documentation generation
  DscResource.Test:
    - 'Task.*'                        # HQRM test tasks
```

### DSC-Specific Pester and HQRM Configuration

DSC projects typically have two Pester configuration blocks — one for standard tests and one for HQRM (High Quality Resource Module) tests:

```yaml
# Standard Pester tests (QA, unit)
Pester:
  Configuration:
    Run:
      Path:
        - tests/QA
    Output:
      Verbosity: Detailed
      StackTraceVerbosity: Full
      CIFormat: Auto
    CodeCoverage:
      CoveragePercentTarget: 0
      OutputPath: JaCoCo_coverage.xml
      OutputEncoding: ascii
      UseBreakpoints: false
    TestResult:
      OutputFormat: NUnitXML
      OutputEncoding: ascii
  ExcludeFromCodeCoverage:

# HQRM tests (DscResource.Test)
DscTest:
  Pester:
    Configuration:
      Filter:
        ExcludeTag:
          - BuiltModule Tests - Validate Localization
      Output:
        Verbosity: Detailed
        CIFormat: Auto
      TestResult:
        OutputFormat: NUnitXML
        OutputEncoding: ascii
        OutputPath: ./output/testResults/NUnitXml_HQRM_Tests.xml
  Script:
    ExcludeSourceFile:
      - output
    ExcludeModuleFile:
      - MyDscProject.psm1
    MainGitBranch: main
```

### Sampler.DscPipeline Configuration

Configure DSC composite resource modules in `build.yaml`:

```yaml
Sampler.DscPipeline:
  DscCompositeResourceModules:
    - PSDesiredStateConfiguration
    - DscConfig.Demo
    # Optionally pin version:
    # - Name: CommonTasks
    #   Version: 0.3.259
```

### SetPSModulePath for DSC Isolation

DSC projects should isolate `PSModulePath` to prevent conflicts between system-installed and build-local modules:

```yaml
SetPSModulePath:
  RemovePersonal: true
  RemoveProgramFiles: true
```

### DSC RequiredModules.psd1

DSC projects require additional dependencies beyond standard build tools:

```powershell
@{
    PSDependOptions              = @{
        AddToPath  = $true
        Target     = 'output\RequiredModules'
        Parameters = @{
            Repository      = 'PSGallery'
            AllowPreRelease = $true
        }
    }

    # Build infrastructure
    InvokeBuild                  = '5.14.22'
    PSScriptAnalyzer             = '1.24.0'
    Pester                       = '5.7.1'
    Plaster                      = '1.1.4'
    ModuleBuilder                = '3.1.8'
    ChangelogManagement          = '3.1.0'
    Sampler                      = '0.118.3'
    'Sampler.GitHubTasks'        = '0.3.5-preview0002'
    'Sampler.AzureDevOpsTasks'   = '0.1.2'
    'Sampler.DscPipeline'        = '0.3.0'
    'powershell-yaml'            = '0.4.12'
    MarkdownLinkCheck            = '0.2.0'
    PowerShellForGitHub          = '0.17.0'

    # DSC build helpers and testing
    'DscResource.AnalyzerRules'  = '0.2.0'
    'DscResource.Test'           = '0.18.0'
    'DscResource.DocGenerator'   = '0.13.0'
    DscBuildHelpers              = '0.3.0'
    xDscResourceDesigner         = '1.13.0.0'

    # Datum (configuration data management)
    Datum                        = '0.41.0'
    'Datum.ProtectedData'        = '0.0.1'
    'Datum.InvokeCommand'        = '0.3.0'
    ProtectedData                = '5.0.0'
    Configuration                = '1.6.0'
    Metadata                     = '1.5.7'

    # DSC resources (domain-specific)
    PSDesiredStateConfiguration  = '2.0.7'
    GuestConfiguration           = '4.11.0'
    ComputerManagementDsc        = '10.0.0'
    NetworkingDsc                = '9.1.0'
    WebAdministrationDsc         = '4.2.1'
    SecurityPolicyDsc            = '2.10.0.0'

    # Azure modules (for Guest Configuration publishing)
    'Az.Accounts'                = '4.0.2'
    'Az.Storage'                 = '8.2.0'
    'Az.Resources'               = '7.9.0'
}
```

### DSC-Specific Build Output

DSC builds produce multiple artifact types (not just a module package):

```text
output/
├── Module/                        # Built module (BuiltModuleSubDirectory)
│   └── MyDscProject/
│       └── 0.4.0/
├── MOF/                           # Compiled MOF files (one per node)
│   ├── DSCFile01.mof
│   ├── DSCWeb01.mof
│   └── *.mof.checksum
├── MetaMOF/                       # Meta MOF files (LCM configuration)
├── RSOP/                          # Resultant Set of Policy (JSON)
├── CompressedModules/             # Zipped DSC resource modules
├── GCPackages/                    # Guest Configuration packages
├── testResults/                   # Test results (NUnit XML)
└── RequiredModules/               # Downloaded dependencies
```

### DSC Testing Categories

DSC projects use specialized test categories beyond standard unit/integration tests:

#### Acceptance Tests (Post-Build Verification)

Acceptance tests verify that build artifacts were created correctly:

```powershell
# tests/Acceptance/TestMofFiles.Tests.ps1
BeforeDiscovery {
    $datumDefinitionFile = Join-Path -Path $ProjectPath -ChildPath source\Datum.yml
    $datum = New-DatumStructure -DefinitionFile $datumDefinitionFile
    $configurationData = Get-FilteredConfigurationData -Filter $Filter

    $mofFiles = Get-ChildItem -Path "$OutputDirectory\MOF" -Filter *.mof -Recurse
    $mofChecksumFiles = Get-ChildItem -Path "$OutputDirectory\MOF" -Filter *.mof.checksum -Recurse
    $metaMofFiles = Get-ChildItem -Path "$OutputDirectory\MetaMOF" -Filter *.mof -Recurse
    $nodes = $configurationData.AllNodes
}

Describe 'MOF Files' -Tag BuildAcceptance {
    It 'All nodes have a MOF file' -TestCases $allMofTests {
        $mofFiles.Count | Should -Be $nodes.Count
    }

    It "Node '<NodeName>' should have a MOF file" -TestCases $individualTests {
        $MofFiles | Where-Object BaseName -EQ $NodeName |
            Should -BeOfType System.IO.FileSystemInfo
    }
}
```

#### ConfigData Tests (Configuration Data Validation)

ConfigData tests validate the Datum YAML structure before compilation:

```powershell
# tests/ConfigData/ConfigData.Tests.ps1
BeforeDiscovery {
    $configurationData = Get-FilteredConfigurationData
    $datumDefinitionFile = Join-Path -Path $ProjectPath -ChildPath source\Datum.yml
    $datum = New-DatumStructure -DefinitionFile $datumDefinitionFile

    $environments = Get-ChildItem $ProjectPath\source\Environments -EA SilentlyContinue |
        Select-Object -ExpandProperty BaseName
    $locations = Get-ChildItem $ProjectPath\source\Locations -EA SilentlyContinue |
        Select-Object -ExpandProperty BaseName
    $roles = Get-ChildItem $ProjectPath\source\Roles -EA SilentlyContinue |
        Select-Object -ExpandProperty BaseName
}

Describe 'Datum Definition' -Tag ConfigData {
    It 'Datum.yml exists' {
        Test-Path $datumDefinitionFile | Should -BeTrue
    }

    It 'Datum.yml is valid YAML' {
        $datumYamlContent | Should -Not -BeNullOrEmpty
    }
}
```

#### CompositeResources Tests

Tests verify that DSC composite resources have all required module dependencies:

```powershell
# tests/ConfigData/CompositeResources.Tests.ps1
BeforeDiscovery {
    $dscCompositeResourceModules = $BuildInfo.'Sampler.DscPipeline'.DscCompositeResourceModules
    # Scans composite resource .psm1 files for Import-DscResource statements
    # and verifies referenced modules are in RequiredModules.psd1
}

Describe "Composite resource '<compositeResourceModuleName>'" -Tag ConfigData {
    It "Should have required module '<ModuleName>' in RequiredModules.psd1" {
        $dscResources.Keys | Should -Contain $ModuleName
    }
}
```

### DSC CI/CD Pipeline Variants

DSC projects often maintain multiple pipeline files for different deployment scenarios:

#### Standard Pipeline (Cloud-Hosted Agents)

The standard pipeline builds on both PowerShell 5.1 and PowerShell 7 in parallel, publishes multiple artifact types, and runs HQRM tests:

```yaml
# azure-pipelines.yml
stages:
  - stage: Build
    jobs:
      - job: CompileDscOnWindowsPowerShell
        displayName: Compile DSC Configuration on Windows PowerShell 5.1
        pool:
          vmImage: 'windows-latest'
        steps:
          - task: PowerShell@2
            name: build
            inputs:
              filePath: './build.ps1'
              arguments: '-ResolveDependency -tasks build'
              pwsh: false              # Windows PowerShell 5.1
            env:
              ModuleVersion: $(NuGetVersionV2)
          - task: PowerShell@2
            name: pack
            inputs:
              filePath: './build.ps1'
              arguments: '-tasks pack'

          # Publish multiple artifact types
          - task: PublishPipelineArtifact@1
            inputs:
              targetPath: '$(buildFolderName)/MOF'
              artifact: 'MOF5'
          - task: PublishPipelineArtifact@1
            inputs:
              targetPath: '$(buildFolderName)/MetaMOF'
              artifact: 'MetaMOF5'
          - task: PublishPipelineArtifact@1
            inputs:
              targetPath: '$(buildFolderName)/CompressedModules'
              artifact: 'CompressedModules5'
          - task: PublishPipelineArtifact@1
            inputs:
              targetPath: '$(buildFolderName)/RSOP'
              artifact: 'RSOP5'

      - job: CompileDscOnPowerShellCore
        # Same build but with pwsh: true for PS7
        # Also publishes GCPackages if they exist

  - stage: Test
    dependsOn: Build
    jobs:
      - job: Test_HQRM
        displayName: 'HQRM'
        steps:
          - task: PowerShell@2
            name: test
            inputs:
              filePath: './build.ps1'
              arguments: '-Tasks hqrmtest'
              pwsh: true
```

#### On-Premises Pipeline (Self-Hosted Agents)

For air-gapped or internal deployments with a private PowerShell repository:

```yaml
# azure-pipelines On-Prem.yml
variables:
  PSModuleFeed: PowerShell
  RepositoryUri: RepositoryUri_WillBeChanged  # Replaced during lab deployment

stages:
  - stage: build
    jobs:
      - job: Dsc_Build
        pool:
          name: Default             # Self-hosted agent pool
        steps:
          - task: PowerShell@2
            displayName: Register PowerShell Gallery
            inputs:
              targetType: inline
              script: |
                $uri = '$(RepositoryUri)'
                $name = 'PowerShell'
                $r = Get-PSRepository -Name $name -ErrorAction SilentlyContinue
                if (-not $r -or $r.SourceLocation -ne $uri) {
                    Unregister-PSRepository -Name $name -ErrorAction SilentlyContinue
                    Register-PSRepository -Name $name -SourceLocation $uri `
                        -PublishLocation $uri -InstallationPolicy Trusted
                }
```

#### Guest Configuration Pipeline

For Azure Policy Guest Configuration with service principal authentication:

```yaml
# azure-pipelines Guest Configuration.yml
stages:
  - stage: Build
    jobs:
      - job: CompileDscOnPowerShellCore
        steps:
          - task: AzureCLI@2
            name: setVariables
            inputs:
              azureSubscription: GC1
              scriptType: ps
              addSpnToEnvironment: true
              inlineScript: |
                Write-Host "##vso[task.setvariable variable=azureClientId;isOutput=true]$($env:servicePrincipalId)"
                Write-Host "##vso[task.setvariable variable=azureClientSecret;isOutput=true]$($env:servicePrincipalKey)"
                Write-Host "##vso[task.setvariable variable=azureIdToken;isOutput=true]$($env:idToken)"

          - task: PowerShell@2
            name: pack
            inputs:
              filePath: './build.ps1'
              arguments: '-tasks pack'
              pwsh: true
            env:
              azureClientId: $(setVariables.azureClientId)
              azureClientSecret: $(setVariables.azureClientSecret)
              azureIdToken: $(setVariables.azureIdToken)
```

### DSC Custom Build Task Patterns

DscWorkshop demonstrates several advanced custom build task patterns:

#### Conditional Task Execution

Use the `-if` parameter to conditionally execute tasks:

```powershell
# .build/PowerShell5Compatibility.ps1
task PowerShell5Compatibility -if ($PSVersionTable.PSEdition -eq 'Desktop') {
    $path = "$requiredModulesPath\PSDesiredStateConfiguration"
    if (Test-Path -Path $path) {
        Remove-Item -Path $path -ErrorAction Stop -Recurse -Force
        Write-Warning "'PSDesiredStateConfiguration' > 2.0 is not supported on Windows PowerShell."
    }
}
```

#### Tasks with `Set-SamplerTaskVariable`

Use `Set-SamplerTaskVariable` for proper initialization of build variables:

```powershell
# .build/GuestConfigurationTasks.ps1
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

task build_guestconfiguration_packages_from_MOF -if (
    $PSVersionTable.PSEdition -eq 'Core'
) {
    # Initialize standard task variables
    . Set-SamplerTaskVariable -AsNewBuild

    $mofPath = Join-Path -Path $OutputDirectory -ChildPath $MofOutputFolder
    $mofFiles = Get-ChildItem -Path $mofPath -Filter '*.mof' -Recurse

    foreach ($mofFile in $mofFiles) {
        $NewGCPackageParams = @{
            Configuration = $mofFile.FullName
            Name          = $mofFile.BaseName
            Path          = $GCPackageOutput
            Force         = $true
            Version       = $ModuleVersion
            Type          = 'AuditAndSet'
        }
        New-GuestConfigurationPackage @NewGCPackageParams
    }
}
```

#### MOF Encoding Conversion Task

```powershell
# .build/ConvertMofFilesToUnicode.ps1
task ConvertMofFilesToUnicode {
    $path = Join-Path -Path $OutputDirectory -ChildPath $MofOutputFolder
    Get-ChildItem -Path $path -Recurse -Filter *.mof | ForEach-Object {
        Write-Host "Converting file $($_.FullName) to Unicode encoding." -ForegroundColor DarkGray
        $content = Get-Content $_.FullName -Encoding UTF8
        $content | Out-File -FilePath $_.FullName -Encoding unicode
    }
}
```

### TaskHeader Formatting

Customize the terminal output decoration for build tasks:

```yaml
TaskHeader: |
  param($Path)
  ""
  "=" * 79
  Write-Build Cyan "`t`t`t$($Task.Name.replace("_"," ").ToUpper())"
  Write-Build DarkGray  "$(Get-BuildSynopsis $Task)"
  "-" * 79
  Write-Build DarkGray "  $Path"
  Write-Build DarkGray "  $($Task.InvocationInfo.ScriptName):$($Task.InvocationInfo.ScriptLineNumber)"
  ""
```

### PullRequestConfig for Azure DevOps

Configure automated changelog PR creation for Azure DevOps Server:

```yaml
PullRequestConfig:
  BranchName: updateChangelogAfterv{0}
  Title: Updating Changelog since release of v{0} +semver:skip
  Description: Updating Changelog since release of v{0} +semver:skip
  Instance: mydevops:8080
  Collection: AutomatedLab
  Project: DscConfig.Demo
  RepositoryID: DscConfig.Demo
  Debug: false
```

---

