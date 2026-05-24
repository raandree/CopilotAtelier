---
name: datum-configuration
description: >-
  Reference for the Datum PowerShell DSC configuration data module: hierarchical data composition, Datum.yml, resolution precedence, merge strategies (MostSpecific, hash, deep, UniqueKeyValTuples, DeepTuple), knockout prefix, lookup_options, DatumStructure, store providers, Datum handlers (InvokeCommand, ProtectedData), RSOP, Roles/Configurations pattern, and the DscWorkshop reference. Includes ProjectDagger patterns: 15-layer hierarchy, Scenario overrides (Tiny/Normal/Extended), ServiceTag-scoped roles, TinyAdditionalRole, cross-domain refs, conditional precedence. USE FOR: Datum, Datum.yml, ResolutionPrecedence, lookup_options, merge strategy, MostSpecific, deep/hash merge, UniqueKeyValTuples, DeepTuple, knockout prefix, RSOP, Get-DatumRsop, Resolve-NodeProperty, Lookup, New-DatumStructure, DatumHandlers, Protect-Datum, DSC config data, Roles pattern, DscWorkshop, Sampler.DscPipeline, Scenario/Tiny override, ServiceTag role. DO NOT USE FOR: Sampler build framework, build debugging, AutomatedLab.
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

Full ``Datum.yml`` schema — ``ResolutionPrecedence``, ``DatumStructure``, ``DefaultProvider``, ``DatumHandlers``, ``Merge_Options``, and worked examples for each key — read [`references/datum-yml-reference.md`](references/datum-yml-reference.md).

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

ProjectDagger conventions: 15-layer hierarchy, Scenario overrides (Tiny/Normal/Extended), ServiceTag-scoped roles, ``TinyAdditionalRole``, cross-domain refs, and conditional precedence rules — read [`references/projectdagger-patterns.md`](references/projectdagger-patterns.md).

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

## DscWorkshop Reference Implementation

DscWorkshop layout, ``Sampler.DscPipeline`` integration, baseline + role + scenario composition, and MOF-build pipeline — read [`references/dscworkshop-reference.md`](references/dscworkshop-reference.md).

## CommonTasks DSC Composite Resources

``CommonTasks`` composite resource catalogue: every composite, its parameter shape, and how to wire it into a Datum role — read [`references/common-tasks.md`](references/common-tasks.md).

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
