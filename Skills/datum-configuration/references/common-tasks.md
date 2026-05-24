# CommonTasks DSC Composite Resources

Extracted from `Skills/datum-configuration/SKILL.md` to keep the main skill body under Anthropic's 500-line budget.

## Contents

- How CommonTasks Work
- Available Composite Resources (CommonTasks)
- Writing a CommonTasks Composite Resource
- YAML Data Schema for CommonTasks
- Frequently Used Configurations and Their Data

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

