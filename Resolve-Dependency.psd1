@{
    <#
        Default parameter values loaded by Resolve-Dependency.ps1 unless overridden
        by bound parameters when the script is called.
    #>

    Gallery                                    = 'PSGallery'

    AllowPrerelease                            = $false

    # Bootstraps PowerShell-Yaml so build.yaml and other configuration files can be read.
    WithYAML                                   = $true

    UsePSResourceGet                           = $true
    PSResourceGetVersion                       = '1.0.1'

    # The PowerShellGet compatibility module only works when PSResourceGet or ModuleFast is used.
    UsePowerShellGetCompatibilityModule        = $true
    UsePowerShellGetCompatibilityModuleVersion = '3.0.23-beta23'
}
