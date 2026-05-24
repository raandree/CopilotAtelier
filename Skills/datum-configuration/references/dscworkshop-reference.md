# DscWorkshop Reference Implementation

Extracted from `Skills/datum-configuration/SKILL.md` to keep the main skill body under Anthropic's 500-line budget.

## Contents

- What DscWorkshop Provides
- Build Pipeline Flow
- Build Filtering
- Key Build Tasks (Sampler.DscPipeline)
- RootConfiguration Pattern (DscWorkshop)
- DscWorkshop Output Structure
- GPO to DSC Migration

[DscWorkshop](https://github.com/dsccommunity/DscWorkshop) is the reference blueprint
for DSC projects using Datum. It demonstrates the complete pipeline from configuration
data to deployed MOF files.

### What DscWorkshop Provides

- Complete build pipeline (Sampler + Sampler.DscPipeline) for MOF compilation
- 7-layer Datum hierarchy (AllNodes, Environment, Locations, Roles, Baselines, Global)
- Pull server deployment with certificate-based encryption
- Automated lab infrastructure via AutomatedLab
- CI/CD integration (Azure Pipelines, Azure DevOps Server, AppVeyor, GitLab)
- Automated testing of configuration data and MOF integrity
- GPO to DSC migration toolkit
- Azure Machine Configuration (Guest Configuration) support

### Build Pipeline Flow

```
build.ps1
  |
  v
Resolve-Dependency (download modules from gallery)
  |
  v
LoadDatumConfigData (load Datum.yml, build $Datum tree)
  |
  v
ConfigDataPreparation (set $ps PullServer variable, validate prerequisites)
  |
  v
CompileDatumRsop (compute RSOP for every node)
  |
  v
CompileRootConfiguration (generate MOF from RSOP via RootConfiguration)
  |
  v
CompileRootMetaMof (generate Meta MOF for LCM configuration)
  |
  v
NewMofChecksums (create checksums for pull server)
  |
  v
CompressModulesWithChecksum (package DSC resource modules)
  |
  v
CompressArtifactCollections (package for deployment)
  |
  v
TestBuildAcceptance + TestConfigData (Pester validation)
```

### Build Filtering

Filter which nodes to compile during local development:

```powershell
# All nodes in environment T01U01, Tiny scenario
.\Build.ps1 -Filter { $_.Environment -eq 'T01U01' -and $_.Scenario -contains 'Tiny' }

# Single node
.\Build.ps1 -Filter { $_.NodeName -eq 'VCMNOC001' }
```

Note: The filter must not exclude the PullServer node — `ConfigDataPreparation` requires it.

### Key Build Tasks (Sampler.DscPipeline)

| Task | Purpose |
|---|---|
| LoadDatumConfigData | Load Datum hierarchy and build `$ConfigurationData` |
| CompileDatumRsop | Compute RSOP for all filtered nodes |
| CompileRootConfiguration | Generate MOF files from RSOP data |
| CompileRootMetaMof | Generate Meta MOF (LCM settings) |
| NewMofChecksums | Create `.mof.checksum` files for pull server |
| CompressModulesWithChecksum | Package DSC resource modules as ZIP |
| CompressArtifactCollections | Package MOFs and modules for deployment |
| TestBuildAcceptance | Run acceptance tests on compiled artifacts |
| TestConfigData | Validate configuration data integrity |

### RootConfiguration Pattern (DscWorkshop)

```powershell
configuration RootConfiguration {
    $rsopCache = Get-DatumRsopCache

    node $ConfigurationData.AllNodes.NodeName {
        $configurationNames = $rsopCache."$($Node.Name)".Configurations

        foreach ($configurationName in $configurationNames) {
            $clonedProperties = $rsopCache."$($Node.Name)".$configurationName
            (Get-DscSplattedResource -ResourceName $configurationName `
                -ExecutionName $configurationName `
                -Properties $clonedProperties -NoInvoke).Invoke($clonedProperties)
        }
    }
}
```

This uses RSOP cache (not live lookups) for performance. Each Configuration listed
in the node's `Configurations` key is looked up, and its data is splatted into the
corresponding DSC Composite Resource.

### DscWorkshop Output Structure

```
output/
  MOF/                    # Compiled .mof files per node
  MetaMOF/                # LCM configuration .meta.mof files
  RSOP/                   # Resolved config data per node (YAML)
  RsopWithSource/         # RSOP with source file tracking
  CompressedModules/      # Packaged DSC resource modules
  CompressedArtifacts/    # Deployment packages
  Logs/                   # Build logs
  Certificates/           # Encryption certificates
```

### GPO to DSC Migration

DscWorkshop includes a toolkit in `GPOs/` for migrating Group Policy Objects to DSC:

- 8 extraction scripts: Security Options, Administrative Templates, Audit Policies,
  Firewall Profiles, Registry Settings, User Rights, System Services
- 2 analysis scripts: duplicate detection and conflict analysis
- 98% coverage (255 of 257 GPO settings)
- Outputs DSC-ready YAML for direct use in Datum hierarchy

---

