# ProjectDagger-Specific Patterns

Extracted from `Skills/datum-configuration/SKILL.md` to keep the main skill body under Anthropic's 500-line budget.

## Contents

- 15-Layer Resolution Hierarchy
- Scenario Override Pattern
- TinyAdditionalRole Mechanism
- ServiceTag-Scoped Roles
- Cross-Domain References
- The $ps Variable Pattern
- Environment Credentials Access

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

