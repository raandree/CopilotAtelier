# Datum.yml Reference

Extracted from `Skills/datum-configuration/SKILL.md` to keep the main skill body under Anthropic's 500-line budget.

## Contents

- DatumStructure
- ResolutionPrecedence
- default_lookup_options
- lookup_options
- DatumHandlers
- Other Settings

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

