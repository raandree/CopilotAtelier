---
name: datum-configuration
description: >-
  Comprehensive reference for the Datum PowerShell DSC configuration data module.
  Covers hierarchical data composition, Datum.yml configuration, resolution
  precedence, merge strategies (MostSpecific, hash, deep, UniqueKeyValTuples,
  DeepTuple), knockout prefix, lookup_options, DatumStructure, store providers,
  Datum handlers (InvokeCommand, ProtectedData), RSOP computation, Roles and
  Configurations pattern, variable substitution in paths, and the DscWorkshop
  reference implementation. Includes ProjectDagger-specific patterns: 15-layer
  hierarchy, Scenario-based overrides (Tiny/Normal/Extended), ServiceTag-scoped
  roles, TinyAdditionalRole mechanism, cross-domain references, and conditional
  resolution precedence entries.
  USE FOR: Datum, Datum.yml, ResolutionPrecedence, lookup_options, merge strategy,
  MostSpecific, deep merge, hash merge, UniqueKeyValTuples, DeepTuple, tuple_keys,
  knockout prefix, RSOP, Resultant Set of Policy, Get-DatumRsop, Resolve-NodeProperty,
  Lookup, New-DatumStructure, DatumHandlers, InvokeCommand, ProtectedData, encrypted
  credentials, Protect-Datum, DSC configuration data, hierarchical data, Roles pattern,
  Configurations key, DscWorkshop, DscConfig.Demo, CommonTasks, Sampler.DscPipeline,
  Scenario override, Tiny override, ServiceTag role, TinyAdditionalRole, data layers,
  node data, role data, baseline data, environment data, location data, cross-datum
  reference, conditional precedence, composite resource, DSC composite, WindowsFeatures,
  ComputerSettings, NetworkIpConfiguration, FilesAndFolders, SoftwarePackages,
  ScomComponents, SqlServer, SharePointProvisioning, RenameNetworkAdapters, DscTagging,
  Get-DscSplattedResource, RootConfiguration, build pipeline, MOF compilation,
  GPO to DSC migration, DSC pull server, release pipeline model.
  DO NOT USE FOR: Sampler build framework (use sampler-framework), debugging Sampler
  builds (use sampler-build-debug), AutomatedLab deployments (use automatedlab-deployment),
  general Pester testing (use pester-patterns), DSC resource development.
---

# Datum — Hierarchical DSC Configuration Data

Comprehensive reference for [Datum](https://github.com/gaelcolas/datum) (v0.41+),
a PowerShell module that aggregates configuration data from multiple sources in a
hierarchical model. Designed primarily for DSC Configuration Data but usable anywhere
hierarchical data lookup and merging is needed.

> **Related skills**: For Sampler build framework, see `sampler-framework`.
> For build debugging, see `sampler-build-debug`. For AutomatedLab, see `automatedlab-deployment`.

---

## Core Concepts

### What Datum Does

Datum organises Configuration Data in a hierarchy adapted to your business context
and injects it into DSC Configurations based on nodes and the roles they implement.
Inspired by Puppet Hiera, Chef Databags, and Ansible Roles.

### Key Terminology

| Term | Definition |
|---|---|
| Datum Tree | The full hierarchical data structure created by `New-DatumStructure` |
| Store / Branch | A root-level data source (e.g., AllNodes, Roles, Baselines) |
| Layer | One entry in ResolutionPrecedence — a path prefix to search |
| Node | A target machine with metadata (NodeName, Role, Environment, etc.) |
| Role | A YAML file defining which Configurations to apply and their data |
| Configuration | A DSC Composite Resource that consumes splatted data |
| RSOP | Resultant Set of Policy — the fully merged data for a node |
| Lookup | The process of resolving a property path through the hierarchy |
| Merge Strategy | Rules governing how values from multiple layers combine |
| Handler | A filter+action pair that transforms values at lookup time |
| Knockout Prefix | The `--` prefix that removes items during merge |

### Data Flow

```
Datum.yml defines hierarchy
        |
        v
Node metadata selects layers --> ResolutionPrecedence paths resolved
        |
        v
Each property looked up through layers (most specific first)
        |
        v
Merge strategy applied per key --> lookup_options
        |
        v
Handlers transform values --> [x= ...=], [ENC= ...=]
        |
        v
RSOP = fully resolved config data for the node
        |
        v
RootConfiguration applies RSOP to generate MOF
```

---

## Datum.yml Reference

The central config file at the root of the configuration data tree.

### DatumStructure

Defines root branches (stores) of the Datum tree:

```yaml
DatumStructure:
  - StoreName: AllNodes
    StoreProvider: Datum::File
    StoreOptions:
      Path: ./AllNodes
  - StoreName: Roles
    StoreProvider: Datum::File
    StoreOptions:
      Path: ./Roles
```

Each StoreName becomes a top-level key in `$Datum` (e.g., `$Datum.AllNodes`).
Custom store providers: `<ModuleName>::<ProviderName>` maps to `New-Datum<ProviderName>Provider`.

### ResolutionPrecedence

Ordered list of path prefixes from most specific to most generic:

```yaml
ResolutionPrecedence:
  - 'AllNodes\$($Node.Environment)\$($Node.Name)'
  - 'Environment\$($Node.Environment)'
  - 'Locations\$($Node.Location)'
  - 'Roles\$($Node.Role)'
  - 'Baselines\$($Node.Baseline)'
  - 'Baselines\ServerBaseline'
```

Rules:
- Use backslash `\` as path separator
- First segment must match a StoreName
- `$Node` properties substituted at lookup time
- `$Node.Name` = file name (set by FileProvider); `$Node.NodeName` = value in data file
- Paths resolving to null/empty are silently skipped

Conditional entries using InvokeCommand (multi-line YAML block scalar `|`):

```yaml
  - |
    '[x= {
      if ($Node.SomeProperty) { "Roles\SpecialRole" }
      # Returns $null if condition not met — entry skipped
    } =]'
```

### default_lookup_options

Global default merge strategy:

```yaml
default_lookup_options: MostSpecific   # or: hash, deep, or detailed hashtable
```

### lookup_options

Per-key merge strategy overrides:

```yaml
lookup_options:
  Configurations:
    merge_basetype_array: Unique
  SoftwarePackages:
    merge_hash: deep
  SoftwarePackages\Packages:
    merge_hash_array: UniqueKeyValTuples
    merge_options:
      tuple_keys:
        - Name
  ^LCM_Config\\.*: deep               # regex pattern (starts with ^)
```

Important — to merge nested keys, declare strategies at EACH level:

```yaml
  SoftwarePackages: deep               # must declare this...
  SoftwarePackages\Packages:           # ...for this to work during top-level lookup
    merge_hash_array: DeepTuple
```

Without `SoftwarePackages: deep`, a lookup of `SoftwarePackages` returns MostSpecific
(no merge) and the Packages rule is never reached. A direct lookup of
`SoftwarePackages\Packages` works because it bypasses the top level.

### DatumHandlers

```yaml
DatumHandlers:
  Datum.ProtectedData::ProtectedDatum:
    CommandOptions:
      PlainTextPassword: SomeSecret     # Testing only! Use Certificate in prod
  Datum.InvokeCommand::InvokeCommand:
    SkipDuringLoad: true                # Evaluate only at lookup, not file load
```

### Other Settings

| Setting | Type | Default | Description |
|---|---|---|---|
| DatumHandlersThrowOnError | bool | false | Surface handler errors as terminating. Recommended: true |
| DscLocalConfigurationManagerKeyName | string | — | Key name for LCM settings in RSOP |
| default_json_depth | int | 4 | ConvertTo-Json depth for debug output |

---

## Merge Strategies

### Data Types for Merge

| Type | Description | Example |
|---|---|---|
| BaseType | Scalars | string, int, bool, DateTime, PSCredential |
| Hashtable | Hashtable/OrderedDictionary | `@{ Key = 'Value' }` |
| baseType_array | Array of scalars | `@('a', 'b')` |
| hash_array | Array of hashtables | `@(@{ Name = 'x' })` |

### Strategy Presets

| Preset | merge_hash | merge_baseType_array | merge_hash_array | knockout |
|---|---|---|---|---|
| MostSpecific / First | MostSpecific | MostSpecific | MostSpecific | none |
| hash / MergeTopKeys | hash | MostSpecific | MostSpecific | `--` |
| deep / MergeRecursively | deep | Unique | DeepTuple | `--` |

### Detailed Strategy Properties

```yaml
lookup_options:
  MyKey:
    merge_hash: MostSpecific | hash | deep
    merge_basetype_array: MostSpecific | Sum | Unique
    merge_hash_array: MostSpecific | Sum | UniqueKeyValTuples | DeepTuple
    merge_options:
      knockout_prefix: '--'
      tuple_keys:
        - Name
        - Version
```

### Hash-Array Merge Strategies

| Strategy | Behaviour |
|---|---|
| MostSpecific | Return array from most specific layer only |
| Sum | Concatenate all arrays |
| UniqueKeyValTuples | Merge arrays, dedup by tuple_keys. Most specific wins. Items REPLACED entirely |
| DeepTuple | Match items by tuple_keys, then DEEP-MERGE matched items' properties |

### Knockout Prefix

The `--` prefix (configurable) removes items during merge:

```yaml
# Baseline (lower priority)
WindowsFeatures:
  Names:
    - Telnet-Client
    - File-Services

# Role override (higher priority)
WindowsFeatures:
  Names:
    - --Telnet-Client        # Removes Telnet-Client from result
```

Works for: base-type arrays, hashtable keys (prefix key name), and hash-array items
(prefix tuple key value). Requires `hash` or `deep` preset, or explicit knockout_prefix.
Does NOT work with MostSpecific (no merge occurs).

---

## Datum Handlers

### InvokeCommand — Dynamic Expressions

Values wrapped in `[x= ... =]` are evaluated as PowerShell at lookup time.

Scriptblock form (most common):

```yaml
ComputedValue: '[x={ Get-Date -Format "yyyy-MM-dd" }=]'
DomainFqdn: '[x={ $Datum.Environment.$($Node.Environment).DomainFqdn }=]'
```

Expandable string form:

```yaml
LogPath: '[x="C:\Logs\$($Node.Environment)\$($Node.Name)"=]'
```

Available variables inside expressions: `$Datum`, `$Node`, `$File` (FileInfo),
`$PropertyPath`, `$InputObject`, plus any CommandOptions keys.

The `$File` variable is a `[System.IO.FileInfo]` of the current data file:
- `$File.BaseName` = file name without extension
- `$File.Directory.BaseName` = parent directory name

Nested resolution: If result contains `[x= ...=]`, it's recursively resolved.

### ProtectedData — Encrypted Credentials

```yaml
AdminCred: '[ENC=PE9ianM... (encrypted blob) ...=]'
```

Encrypt: `Protect-Datum -InputObject $credential -Certificate $thumbprint`
Decrypt: Happens automatically at lookup time via the handler.

### Building Custom Handlers

Create module with `Test-<Name>Filter` and `Invoke-<Name>Action` functions.
Register in DatumHandlers section of Datum.yml as `<ModuleName>::<HandlerName>`.

---

## RSOP (Resultant Set of Policy)

Computes the fully resolved, merged configuration data for nodes:

```powershell
$Datum = New-DatumStructure -DefinitionFile .\Datum.yml
$rsop = Get-DatumRsop -Datum $Datum -AllNodes $AllNodes

# Specific node
$rsop = Get-DatumRsop -Datum $Datum -AllNodes $AllNodes -Filter { $_.NodeName -eq 'SRV01' }

# With source tracking
$rsop = Get-DatumRsop -Datum $Datum -AllNodes $AllNodes -IncludeSource
```

Cache management:
- `Get-DatumRsopCache` — view cache
- `Clear-DatumRsopCache` — clear after data changes
- `-IgnoreCache` flag on Get-DatumRsop

---

## Roles and Configurations Pattern

### How It Works

1. A Role YAML file lists `Configurations` (DSC Composite Resources) and their data
2. A Node YAML file specifies which Role it implements
3. The RootConfiguration iterates over each node's Configurations and splats the data

### Role File Structure

```yaml
# Roles/FileServer.yml
Configurations:
  - WindowsFeatures
  - FileSystemObjects
  - SmbShares

WindowsFeatures:
  Names:
    - File-Services

FileSystemObjects:
  Items:
    - DestinationPath: C:\Data
      Type: Directory
```

### Node File Structure

```yaml
# AllNodes/Prod/SRV01.yml
NodeName: SRV01
Environment: Prod
Role: FileServer
Location: Frankfurt
Baseline: Server
ServiceTag: PF
```

### RootConfiguration Pattern

```powershell
node $ConfigurationData.AllNodes.NodeName {
    $configurationNames = (Lookup 'Configurations')
    foreach ($configurationName in $configurationNames) {
        $properties = Lookup $configurationName -DefaultValue @{}
        Get-DscSplattedResource -ResourceName $configurationName `
            -ExecutionName $configurationName -Properties $properties
    }
}
```

---

## ProjectDagger-Specific Patterns

### 15-Layer Resolution Hierarchy

```yaml
ResolutionPrecedence:
  - AllNodes\$($Node.Environment)\$($Node.Name)              # 1. Node-specific
  - Hypervisor\$($Hypervisor)                                  # 2. Hypervisor overlay
  - Scenario\$($Scenario)                                      # 3. Scenario defaults
  - '[x={ "Roles\{0}" -f $Node."$($Scenario)AdditionalRole" }=]'  # 4. Scenario additional role
  - Roles\$($Node.ServiceTag)\$($Scenario)$($Node.Role)       # 5. ServiceTag+Scenario+Role
  - Roles\$($Node.ServiceTag)\$($Node.Role)                   # 6. ServiceTag+Role
  - Roles\$($Scenario)$($Node.Role)                           # 7. Scenario+Role
  - Roles\$($Node.Role)                                       # 8. Base Role
  - Locations\$($Node.Location)                                # 9. Location
  - Environment\$($Node.Environment)                           # 10. Environment
  - Baselines\$($Scenario)$($Node.Baseline)                   # 11. Scenario+Baseline
  - Baselines\$($Node.Baseline)                                # 12. Base Baseline
  - Baselines\$($Scenario)                                     # 13. Scenario baseline
  - Baselines\ServerBaseline                                   # 14. Server baseline
  - Baselines\DscBaseline                                      # 15. DSC baseline
```

### Scenario Override Pattern

Lab scenarios (Tiny, Normal, Extended) select different resource levels:

- Tiny: Minimal VMs, co-located services, reduced memory
- Normal: Standard deployment
- Extended: Full HA with clustering, AG, multiple nodes

Override a role for a specific scenario by creating a file at the Scenario+Role level:

```
Roles/TinyScomManagement.yml          # Layer 7: overrides ScomManagement for Tiny
Roles/pf/TinyHaSqlServerFirstNode.yml # Layer 5: PF ServiceTag + Tiny + Role
Roles/ExtendedHaSqlServerFirstNode.yml # Layer 7: Extended scenario override
```

Key rule: With `default_lookup_options: MostSpecific`, each top-level key is independently
resolved. A Tiny override defining only `ScomComponents` overrides just that key — other
keys (`ScomSettings`, `ScomManagementPacks`) still come from the base Role file.

But `Configurations` uses `merge_basetype_array: Unique`, so configuration lists are
merged across layers (not replaced).

### TinyAdditionalRole Mechanism

Nodes specify an additional role for a specific scenario:

```yaml
# Node file
TinyAdditionalRole: ExchangeSingleServer
```

Resolves via layer 4: `Roles\ExchangeSingleServer` — adding Configurations and data.

### ServiceTag-Scoped Roles

ServiceTag (e.g., PF, CM) groups nodes by organizational domain. Overrides live
in subdirectories:

```
Roles/pf/FileServer.yml               # Layer 6: PF-specific FileServer
Roles/cm/RootDomainController.yml      # Layer 6: CM-specific DC
Roles/pf/TinyHaSqlServerFirstNode.yml  # Layer 5: PF + Tiny + Role
```

### Cross-Domain References

When a node in one ServiceTag needs data from another:

```yaml
SqlServerInstance: '[x={$ConfigurationData.AllNodes.Where({$_.Role -eq "HaSqlServerFirstNode" -and $_.ServiceTag -eq "PF"}).NodeName}=]'
```

### The $ps Variable Pattern

The `ConfigDataPreparation` build task sets a global `$ps` variable pointing to
the PullServer node. Datum expressions reference it for UNC paths:

```yaml
SourcePath: '[x={"\\{0}.{1}\SoftwarePackages\..." -f $ps.NodeName, $Datum.Environment.$($Node.Environment).Credentials.$($ps.Name.Substring(1,2)).DomainFqdn}=]'
```

### Environment Credentials Access

```yaml
# Domain FQDN
$Datum.Environment.$($Node.Environment).Credentials.$($Node.ServiceTag).DomainFqdn

# Service account password
$Datum.Environment.$($Node.Environment).Credentials.$($Node.ServiceTag).Users.Where({$_.UserName -eq "SVCACC_SQL"}).Password
```

---

## Public Functions

| Function | Purpose |
|---|---|
| New-DatumStructure | Create Datum hierarchy from Datum.yml |
| Resolve-NodeProperty | DSC-friendly lookup (aliases: Lookup, Resolve-DscProperty) |
| Resolve-Datum | Core lookup engine with merge strategy support |
| Merge-Datum | Merge two datum objects using configured strategy |
| Get-DatumRsop | Compute Resultant Set of Policy |
| Get-DatumRsopCache | View RSOP cache |
| Clear-DatumRsopCache | Clear RSOP cache |
| New-DatumFileProvider | Create file provider for a path |
| Get-FileProviderData | Read and parse data files (YAML, JSON, PSD1) |
| Get-MergeStrategyFromPath | Resolve merge strategy for a property path |
| Get-DatumSourceFile | Get source file path for RSOP source tracking |

---

## Common Troubleshooting

### RSOP Shows Wrong Value

1. Check `lookup_options` — is the key using MostSpecific when deep is needed?
2. Check subkey merge — did you declare strategies at each nesting level?
3. Use `Get-DatumRsop -IncludeSource` to see which file contributed each value
4. Clear cache: `Clear-DatumRsopCache`

### Knockout Not Working

- Verify merge strategy enables knockout (hash or deep preset, or explicit knockout_prefix)
- MostSpecific does NOT support knockout (no merge occurs)

### Expression Not Evaluating

- Check `SkipDuringLoad: true` is set for InvokeCommand handler
- Check `DatumHandlersThrowOnError: true` to surface expression errors
- Verify quoting: YAML single quotes around `[x= ... =]` prevent YAML parsing issues

### Scenario Override Not Applied

- Verify layer order in ResolutionPrecedence
- File name must match exactly: `Roles\$($Scenario)$($Node.Role)` maps to e.g. `TinyScomManagement.yml`
- `Configurations` merges (Unique), but other keys use MostSpecific (replace)

### Node Property Not Available

- `$Node.Name` = file name (set by FileProvider, always available)
- `$Node.NodeName` = value in data file (may not exist during load)
- Use `$Node.Name` for bootstrapping

---

## File System Layout

```
source/
  Datum.yml                          # Central configuration
  RootConfiguration.ps1              # DSC root config
  AllNodes/                          # Node definitions
    <Environment>/
      <NodeName>.yml
  Roles/                             # Role definitions
    <RoleName>.yml
    <ServiceTag>/                    # ServiceTag-scoped overrides
      <RoleName>.yml
      <Scenario><RoleName>.yml
    <Scenario><RoleName>.yml         # Scenario-scoped overrides
  Environment/                       # Environment-level data
    <Environment>.yml
  Locations/                         # Location-specific data
    <Location>.yml
  Baselines/                         # Low-priority defaults
    ServerBaseline.yml
    DscBaseline.yml
    <Scenario>.yml
  Scenario/                          # Scenario settings
    Tiny.yml
    Normal.yml
    Extended.yml
  Hypervisor/                        # Hypervisor-specific
    HyperV.yml
    Azure.yml
```

---

## DscWorkshop — Reference Implementation

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

## CommonTasks — DSC Composite Resources

[CommonTasks](https://github.com/dsccommunity/CommonTasks) provides reusable DSC
Composite Resources (Configurations) designed for Datum-based projects. Each composite
wraps one or more DSC resources and accepts splatted data from Datum YAML files.

### How CommonTasks Work

1. A Role file lists configuration names in its `Configurations` key
2. Each name maps to a CommonTasks composite resource
3. Datum resolves the corresponding data key (same name as the configuration)
4. `Get-DscSplattedResource` splats the data into the composite resource

Example:

```yaml
# Role file
Configurations:
  - WindowsFeatures
  - FilesAndFolders
  - SoftwarePackages

WindowsFeatures:
  Names:
    - File-Services
    - RSAT

FilesAndFolders:
  Items:
    - DestinationPath: C:\Data
      Type: Directory

SoftwarePackages:
  Packages:
    - Name: Notepad++
      Path: '\\server\share\npp.msi'
      ProductId: 'XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX'
```

### Available Composite Resources (CommonTasks)

Grouped by category:

**Active Directory**:
AddsDomain, AddsDomainController, AddsDomainPrincipals, AddsOrgUnitsAndGroups,
AddsProtectFromAccidentalDeletion, AddsServicePrincipalNames, AddsSiteLinks,
AddsSitesSubnets, AddsTrusts, AddsWaitForDomains

**Certificates**:
CertificateAuthorities, CertificateExports, CertificateImports, CertificateRequests

**Compute & OS**:
ComputerSettings, Disks, DiskAccessPaths, MountImages, OpticalDiskDrives,
PowerPlans, RestartSystem, VirtualMemoryFiles, WindowsFeatures,
WindowsOptionalFeatures, WindowsServices, EnvironmentVariables

**DNS**:
DnsServerARecords, DnsServerAdZones, DnsServerCNameRecords,
DnsServerConditionalForwarders, DnsServerForwarders, DnsServerLegacySettings,
DnsServerMxRecords, DnsServerPrimaryZones, DnsServerQueryResolutionPolicies,
DnsServerResponseRateLimiting, DnsServerRootHints, DnsServerSettings,
DnsServerZonesAging, DnsSuffixes

**DHCP**:
DhcpServer, DhcpServerAuthorization, DhcpServerOptionDefinitions,
DhcpServerOptions, DhcpScopes, DhcpScopeOptions

**DSC Infrastructure**:
DscLcmController, DscLcmMaintenanceWindows, DscPullServer, DscPullServerSql,
DscTagging, DscDiagnostic, SwitchLcmMode, WaitForAllNodes, WaitForAnyNode,
WaitForSomeNodes

**Exchange**:
ExchangeAutoMountPoints, ExchangeConfiguration, ExchangeDagProvisioning,
ExchangeMailboxDatabaseCopies, ExchangeMailboxDatabases, ExchangeProvisioning

**File & Share**:
FilesAndFolders, FileContents, SmbShares, DfsNamespaces,
DfsReplicationGroupConnections, DfsReplicationGroupMembers,
DfsReplicationGroupMemberships, Robocopies, XmlContent

**Networking**:
NetworkIpConfiguration, RenameNetworkAdapters, Network, IpConfiguration,
FirewallProfiles, FirewallRules, HostsFileEntries

**Remote Desktop**:
RemoteDesktopCertificates, RemoteDesktopCollections, RemoteDesktopDeployment,
RemoteDesktopHAMode, RemoteDesktopLicensing, RemoteDesktopServers

**SCOM**:
ScomComponents, ScomManagementPacks, ScomSettings

**Security**:
AuditPolicies, Bitlocker, SecurityBase, SecurityPolicies, LocalGroups, LocalUsers,
JeaEndpoints, JeaRoles

**SharePoint**:
SharePointCacheAccounts, SharePointContentDatabases, SharePointManagedAccounts,
SharePointManagedPaths, SharePointPrereq, SharePointProvisioning,
SharePointServiceAppPools, SharePointServiceInstances, SharePointSetup,
SharePointSites, SharePointWebApplications

**Software**:
SoftwarePackages, ChocolateyPackages, ChocolateyPackages2nd, ChocolateyPackages3rd,
Scripts, PowerShellRepositories, PowershellExecutionPolicies

**SQL Server**:
SqlServer, SqlConfigurations, SqlDatabases, SqlLogins, SqlPermissions, SqlRoles,
SqlAGs, SqlAGListeners, SqlAGReplicas, SqlAGDatabases, SqlAlwaysOnServices,
SqlAliases, SqlEndpoints, SqlAgentAlerts, SqlAgentOperators, SqlDatabaseMailSetups,
SqlScriptQueries

**Web / IIS**:
WebApplicationPools, WebApplications, WebSites, WebVirtualDirectories,
WebConfigProperties, WebConfigPropertyCollections, WebBrowser

**Other**:
ConfigurationBase, ConfigurationManagerConfiguration, ConfigurationManagerDeployment,
ConfigurationManagerDistributionGroups, FailoverCluster, HyperV, HyperVReplica,
HyperVState, MmaAgent, OfficeOnlineServerSetup, OfficeOnlineServerFarmConfig,
OfficeOnlineServerMachineConfig, RegistryPolicies, RegistryValues, ScheduledTasks,
UpdateServices, VSTSAgents, Wds, WindowsEventForwarding, WindowsEventLogs

### Writing a CommonTasks Composite Resource

Each composite is a DSC Composite Resource (schema.psm1) that accepts splatted parameters:

```powershell
configuration FilesAndFolders {
    param (
        [Parameter()]
        [hashtable[]]
        $Items
    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration

    foreach ($item in $Items) {
        if (-not $item.Ensure) { $item['Ensure'] = 'Present' }
        $executionName = "file_$($item.DestinationPath -replace '[:\\]', '_')"
        (Get-DscSplattedResource -ResourceName File `
            -ExecutionName $executionName `
            -Properties $item -NoInvoke).Invoke($item)
    }
}
```

The `Get-DscSplattedResource` function (from DscBuildHelpers) dynamically invokes
DSC resources with hashtable parameters, avoiding the need to hardcode every property.

### YAML Data Schema for CommonTasks

Detailed YAML reference documentation for every CommonTasks configuration is maintained
in [DscConfig.Demo/doc/README.adoc](https://github.com/raandree/DscConfig.Demo/tree/main/doc/README.adoc).
This includes parameter schemas, examples, and merge strategy recommendations.

### Frequently Used Configurations and Their Data

**ComputerSettings** — Domain join, computer name, time zone:
```yaml
ComputerSettings:
  Name: SRV01
  DomainName: contoso.com
  Credential: '[ENC=...]'
  JoinOU: 'OU=Servers,DC=contoso,DC=com'
  TimeZone: UTC
  Description: Web Server
```

**WindowsFeatures** — Windows roles and features:
```yaml
WindowsFeatures:
  Names:
    - Web-Server
    - Web-Mgmt-Tools
    - RSAT-DNS-Server
```

**NetworkIpConfiguration** — IP addressing:
```yaml
NetworkIpConfiguration:
  Interfaces:
    - InterfaceAlias: Ethernet0
      IpAddress: 10.0.0.10
      Prefix: 24
      Gateway: 10.0.0.1
      DnsServer:
        - 10.0.0.1
        - 10.0.0.2
      DisableNetbios: true
```

**SoftwarePackages** — MSI/EXE installations:
```yaml
SoftwarePackages:
  Packages:
    - Name: 7-Zip
      Path: '\\server\share\7z.msi'
      ProductId: 'GUID-HERE'
      ReturnCode:
        - 0
        - 3010
```

**DscTagging** — Build metadata in registry:
```yaml
DscTagging:
  Environment: Production
  Version: 1.0.0
  BuildDate: '[x={ Get-Date -Format "yyyy-MM-dd" }=]'
```

---

## DscConfig.Demo

[DscConfig.Demo](https://github.com/raandree/DscConfig.Demo) is the companion module
to CommonTasks, providing additional composite resources and the comprehensive YAML
reference documentation (`doc/README.adoc`) with schema information for all configurations.
ProjectDagger uses DscConfig.Demo alongside CommonTasks in its `RequiredModules.psd1`.

---

## Ecosystem Relationships

```
Datum                    Hierarchical data lookup + merge engine
  |
  v
DscWorkshop              Reference implementation / project blueprint
  |                      Uses: Sampler, Sampler.DscPipeline, Datum
  |
  +-- CommonTasks        DSC Composite Resources (configurations)
  |                      50+ composites: WindowsFeatures, ComputerSettings, etc.
  |
  +-- DscConfig.Demo     Additional composites + YAML reference docs
  |
  +-- DscBuildHelpers    Get-DscSplattedResource, build utilities
  |
  +-- Sampler.DscPipeline  Build tasks: LoadDatumConfigData, CompileRootConfiguration, etc.
  |
  +-- Datum.InvokeCommand  [x= ... =] expression handler
  +-- Datum.ProtectedData  [ENC= ... =] credential encryption handler
```

ProjectDagger extends this ecosystem with project-specific composite resources
(e.g., ScomComponents, SharePointProvisioning) and a 15-layer hierarchy.
