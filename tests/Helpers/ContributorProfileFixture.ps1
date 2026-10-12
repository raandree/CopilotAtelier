<#
    The shared Contributor profile fixture set of Decision record 0028: one
    valid profile and at least one fixture per schema 1 rule. Every entry point
    (the hooks, the Skill script, and the module commands) reads the same bytes
    and must agree on the levels or on exactly one reason code. Aliases use
    example.com; no fixture holds a real address.
#>

function New-ContributorFixtureEntry
{
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter()] [System.String] $Id = '11111111-1111-4111-8111-111111111111',
        [Parameter()] [System.String] $Default = 'false',
        [Parameter()] [System.String] $State = '"on"',
        [Parameter()] [System.String] $StateUpdatedUtc = '"2026-10-01T08:00:00Z"',
        [Parameter()] [System.String] $Snooze = 'null',
        [Parameter()] [System.String] $Aliases = '["ada@example.com"]',
        [Parameter()] [System.String] $Areas = '{"Kerberos":{"level":"new","updatedUtc":"2026-10-01T08:00:00Z"},"PowerShell DSC":{"level":"expert","updatedUtc":"2026-10-01T08:00:00Z"}}',
        [Parameter()] [System.String] $Extra = '',
        [Parameter()] [System.String[]] $Omit = @()
    )

    $member = [ordered] @{
        id                       = '"' + $Id + '"'
        default                  = $Default
        state                    = $State
        stateUpdatedUtc          = $StateUpdatedUtc
        interviewSnoozedUntilUtc = $Snooze
        aliases                  = $Aliases
        areas                    = $Areas
    }

    $parts = foreach ($key in $member.Keys)
    {
        if ($Omit -notcontains $key)
        {
            '"{0}":{1}' -f $key, $member[$key]
        }
    }

    '{' + ($parts -join ',') + $Extra + '}'
}

function New-ContributorFixtureProfile
{
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter()] [System.String[]] $Entry = @((New-ContributorFixtureEntry)),
        [Parameter()] [System.String] $Version = '1',
        [Parameter()] [System.String] $Extra = ''
    )

    '{"schemaVersion":' + $Version + ',"contributors":[' + ($Entry -join ',') + ']' + $Extra + '}'
}

function New-ContributorFixtureId
{
    [CmdletBinding()]
    [OutputType([System.String])]
    param ([Parameter(Mandatory = $true)] [System.Int32] $Number)

    '{0:x8}-0000-4000-8000-{0:x12}' -f $Number
}

function Get-ContributorProfileFixtureCase
{
    <#
        Returns @{ Name; Reason; Text } or @{ Name; Reason; Bytes }. Reason is
        $null for a valid profile, which also carries Levels: its entry's
        levels as 'Name: level' in profile order, the order in which every
        entry point reports them.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param ()

    $area = '{"level":"new","updatedUtc":"2026-10-01T08:00:00Z"}'
    $standardLevels = @('Kerberos: new', 'PowerShell DSC: expert')
    $dotNetAreas = '{"Kerberos":{"level":"new","updatedUtc":"2026-10-01T08:00:00Z"},"PowerShell DSC":{"level":"expert","updatedUtc":"2026-10-01T08:00:00Z"},".NET":{"level":"familiar","updatedUtc":"2026-10-01T08:00:00Z"}}'

    @{ Name = 'valid profile'; Reason = $null; Levels = $standardLevels; Text = (New-ContributorFixtureProfile) }
    @{ Name = 'valid entry without areas or aliases'; Reason = $null; Levels = @(); Text = (New-ContributorFixtureProfile -Entry (New-ContributorFixtureEntry -Aliases '[]' -Areas '{}')) }
    @{ Name = 'valid profile with a byte-order mark'; Reason = $null; Levels = $standardLevels; Bytes = ([byte[]] @(0xEF, 0xBB, 0xBF) + [System.Text.Encoding]::UTF8.GetBytes((New-ContributorFixtureProfile))) }
    @{ Name = 'valid area name that starts with a dot'; Reason = $null; Levels = @($standardLevels + '.NET: familiar'); Text = (New-ContributorFixtureProfile -Entry (New-ContributorFixtureEntry -Areas $dotNetAreas)) }

    @{ Name = 'trailing comma'; Reason = 'invalid-json'; Text = '{"schemaVersion":1,"contributors":[' + (New-ContributorFixtureEntry) + '],}' }
    @{ Name = 'not JSON'; Reason = 'invalid-json'; Text = 'schemaVersion = 1' }
    @{ Name = 'not UTF-8'; Reason = 'invalid-json'; Bytes = [byte[]] @(0x7B, 0x22, 0xFF, 0xFE, 0x22, 0x3A, 0x31, 0x7D) }
    @{ Name = 'two top-level values'; Reason = 'invalid-json'; Text = (New-ContributorFixtureProfile) + ' {}' }

    @{ Name = 'schemaVersion missing'; Reason = 'invalid-schema'; Text = '{"contributors":[' + (New-ContributorFixtureEntry) + ']}' }
    @{ Name = 'schemaVersion as a string'; Reason = 'invalid-schema'; Text = (New-ContributorFixtureProfile -Version '"1"') }
    @{ Name = 'schemaVersion as a fraction'; Reason = 'invalid-schema'; Text = (New-ContributorFixtureProfile -Version '1.0') }
    @{ Name = 'schemaVersion 2'; Reason = 'unsupported-schema'; Text = (New-ContributorFixtureProfile -Version '2') }
    @{ Name = 'unknown property at the root'; Reason = 'invalid-schema'; Text = (New-ContributorFixtureProfile -Extra ',"notes":"likes cats"') }
    @{ Name = 'case-only duplicate root property'; Reason = 'invalid-schema'; Text = (New-ContributorFixtureProfile -Extra ',"Contributors":[]') }
    @{ Name = 'no contributors'; Reason = 'invalid-schema'; Text = (New-ContributorFixtureProfile -Entry @()) }
    @{ Name = 'more than 16 entries'; Reason = 'invalid-schema'; Text = (New-ContributorFixtureProfile -Entry @(
                foreach ($number in 1..17) { New-ContributorFixtureEntry -Id (New-ContributorFixtureId -Number $number) -Aliases ('["p{0}@example.com"]' -f $number) }
            )) }
    @{ Name = 'unknown entry property'; Reason = 'invalid-schema'; Text = (New-ContributorFixtureProfile -Entry (New-ContributorFixtureEntry -Extra ',"notes":"likes cats"')) }
    @{ Name = 'entry without state'; Reason = 'invalid-schema'; Text = (New-ContributorFixtureProfile -Entry (New-ContributorFixtureEntry -Omit 'state')) }
    @{ Name = 'entry not an object'; Reason = 'invalid-schema'; Text = (New-ContributorFixtureProfile -Entry '"ada"') }
    @{ Name = 'id that is not a GUID'; Reason = 'invalid-schema'; Text = (New-ContributorFixtureProfile -Entry (New-ContributorFixtureEntry -Id 'ada')) }
    @{ Name = 'repeated id'; Reason = 'invalid-schema'; Text = (New-ContributorFixtureProfile -Entry @(
                (New-ContributorFixtureEntry)
                (New-ContributorFixtureEntry -Aliases '["bob@example.com"]')
            )) }
    @{ Name = 'two default entries'; Reason = 'invalid-schema'; Text = (New-ContributorFixtureProfile -Entry @(
                (New-ContributorFixtureEntry -Default 'true')
                (New-ContributorFixtureEntry -Id (New-ContributorFixtureId -Number 2) -Default 'true' -Aliases '["bob@example.com"]')
            )) }
    @{ Name = 'default that is not a boolean'; Reason = 'invalid-schema'; Text = (New-ContributorFixtureProfile -Entry (New-ContributorFixtureEntry -Default '"yes"')) }
    @{ Name = 'state in the wrong case'; Reason = 'invalid-schema'; Text = (New-ContributorFixtureProfile -Entry (New-ContributorFixtureEntry -State '"On"')) }
    @{ Name = 'stateUpdatedUtc with an offset'; Reason = 'invalid-schema'; Text = (New-ContributorFixtureProfile -Entry (New-ContributorFixtureEntry -StateUpdatedUtc '"2026-10-01T10:00:00+02:00"')) }
    @{ Name = 'snooze that is not a time'; Reason = 'invalid-schema'; Text = (New-ContributorFixtureProfile -Entry (New-ContributorFixtureEntry -Snooze '"tomorrow"')) }
    @{ Name = 'more than 8 aliases'; Reason = 'invalid-schema'; Text = (New-ContributorFixtureProfile -Entry (New-ContributorFixtureEntry -Aliases ('[' + ((1..9 | ForEach-Object -Process { '"a{0}@example.com"' -f $_ }) -join ',') + ']'))) }
    @{ Name = 'alias that is not an email address'; Reason = 'invalid-schema'; Text = (New-ContributorFixtureProfile -Entry (New-ContributorFixtureEntry -Aliases '["ada"]')) }
    @{ Name = 'alias held by two entries'; Reason = 'invalid-schema'; Text = (New-ContributorFixtureProfile -Entry @(
                (New-ContributorFixtureEntry)
                (New-ContributorFixtureEntry -Id (New-ContributorFixtureId -Number 2) -Aliases '["ADA@example.com"]')
            )) }
    @{ Name = 'more than 200 areas'; Reason = 'invalid-schema'; Text = (New-ContributorFixtureProfile -Entry (New-ContributorFixtureEntry -Areas ('{' + ((1..201 | ForEach-Object -Process { '"Area {0}":{1}' -f $_, $area }) -join ',') + '}'))) }
    @{ Name = 'area name that breaks the rule'; Reason = 'invalid-schema'; Text = (New-ContributorFixtureProfile -Entry (New-ContributorFixtureEntry -Areas ('{"C_Sharp":' + $area + '}'))) }
    @{ Name = 'area name of a lone dot'; Reason = 'invalid-schema'; Text = (New-ContributorFixtureProfile -Entry (New-ContributorFixtureEntry -Areas ('{".":' + $area + '}'))) }
    @{ Name = 'area name of two dots'; Reason = 'invalid-schema'; Text = (New-ContributorFixtureProfile -Entry (New-ContributorFixtureEntry -Areas ('{"..":' + $area + '}'))) }
    @{ Name = 'area name with a dot before a space'; Reason = 'invalid-schema'; Text = (New-ContributorFixtureProfile -Entry (New-ContributorFixtureEntry -Areas ('{". NET":' + $area + '}'))) }
    @{ Name = 'area name that is not normalized'; Reason = 'invalid-schema'; Text = (New-ContributorFixtureProfile -Entry (New-ContributorFixtureEntry -Areas ('{"Kerberos ":' + $area + '}'))) }
    @{ Name = 'case-only duplicate area name'; Reason = 'invalid-schema'; Text = (New-ContributorFixtureProfile -Entry (New-ContributorFixtureEntry -Areas ('{"Kerberos":' + $area + ',"kerberos":' + $area + '}'))) }
    @{ Name = 'level in the wrong case'; Reason = 'invalid-schema'; Text = (New-ContributorFixtureProfile -Entry (New-ContributorFixtureEntry -Areas '{"Kerberos":{"level":"Expert","updatedUtc":"2026-10-01T08:00:00Z"}}')) }
    @{ Name = 'area with an extra property'; Reason = 'invalid-schema'; Text = (New-ContributorFixtureProfile -Entry (New-ContributorFixtureEntry -Areas '{"Kerberos":{"level":"new","updatedUtc":"2026-10-01T08:00:00Z","note":"x"}}')) }
    @{ Name = 'area without updatedUtc'; Reason = 'invalid-schema'; Text = (New-ContributorFixtureProfile -Entry (New-ContributorFixtureEntry -Areas '{"Kerberos":{"level":"new"}}')) }
    @{ Name = 'nesting deeper than any schema 1 file'; Reason = 'invalid-schema'; Text = (New-ContributorFixtureProfile -Extra (',"x":' + ('[' * 20) + (']' * 20))) }
    @{ Name = 'larger than 64 KB'; Reason = 'too-large'; Text = (New-ContributorFixtureProfile) + (' ' * 65536) }
}

function Write-ContributorFixture
{
    <#
        Writes one fixture case to a file, as UTF-8 without a byte-order mark
        unless the case carries raw bytes.
    #>
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)] [hashtable] $Case,
        [Parameter(Mandatory = $true)] [System.String] $Path
    )

    $directory = Split-Path -Path $Path -Parent
    if (-not (Test-Path -LiteralPath $directory))
    {
        $null = New-Item -ItemType Directory -Path $directory -Force
    }

    if ($Case.ContainsKey('Bytes'))
    {
        [System.IO.File]::WriteAllBytes($Path, [byte[]] $Case.Bytes)
    }
    else
    {
        [System.IO.File]::WriteAllText($Path, $Case.Text, [System.Text.UTF8Encoding]::new($false))
    }
}

function New-ContributorTestHome
{
    <#
        Builds a user home whose ~/.copilot/hooks links to the hooks folder of a
        Canonical target holding .copilotatelier.json, the deployed layout.
        Without -Canonical the home has no ~/.copilot, the plugin-only layout.
        Returns the home, the target, and the LocalApplicationData root.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)] [System.String] $Root,
        [Parameter()] [System.Management.Automation.SwitchParameter] $Canonical,
        [Parameter()] [System.Management.Automation.SwitchParameter] $WithFamiliarityScript
    )

    $userHome = Join-Path -Path $Root -ChildPath 'home'
    $target = Join-Path -Path $Root -ChildPath 'CopilotAtelier'
    $localData = Join-Path -Path $Root -ChildPath 'localappdata'
    $null = New-Item -ItemType Directory -Path $userHome, $localData -Force

    if ($Canonical)
    {
        $null = New-Item -ItemType Directory -Path (Join-Path -Path $target -ChildPath 'hooks/scripts') -Force
        Set-Content -LiteralPath (Join-Path -Path $target -ChildPath '.copilotatelier.json') -Value '{}' -Encoding ascii
        if ($WithFamiliarityScript)
        {
            Set-Content -LiteralPath (Join-Path -Path $target -ChildPath 'hooks/scripts/Add-FamiliarityContext.ps1') -Value 'exit 0' -Encoding ascii
        }

        $copilotDirectory = Join-Path -Path $userHome -ChildPath '.copilot'
        $null = New-Item -ItemType Directory -Path $copilotDirectory -Force
        $linkType = if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) { 'Junction' } else { 'SymbolicLink' }
        $null = New-Item -ItemType $linkType -Path (Join-Path -Path $copilotDirectory -ChildPath 'hooks') -Target (Join-Path -Path $target -ChildPath 'hooks')
    }

    [pscustomobject] @{
        Home            = $userHome
        Target          = $target
        LocalData       = $localData
        CanonicalFolder = Join-Path -Path $target -ChildPath 'contributor'
        LocalFolder     = Join-Path -Path $localData -ChildPath 'CopilotAtelier/contributor'
    }
}

function Use-ContributorEnvironment
{
    <#
        Runs a script block with environment variables set, then restores them,
        so a test never leaks a redirected home into the next.
    #>
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)] [hashtable] $Variable,
        [Parameter(Mandatory = $true)] [scriptblock] $ScriptBlock
    )

    $saved = @{}
    foreach ($name in $Variable.Keys)
    {
        $saved[$name] = [System.Environment]::GetEnvironmentVariable($name)
        [System.Environment]::SetEnvironmentVariable($name, $Variable[$name])
    }

    try
    {
        & $ScriptBlock
    }
    finally
    {
        foreach ($name in $saved.Keys)
        {
            [System.Environment]::SetEnvironmentVariable($name, $saved[$name])
        }
    }
}

function New-ContributorGitRepository
{
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)] [System.String] $Path,
        [Parameter()] [System.String] $Email
    )

    $null = New-Item -ItemType Directory -Path $Path -Force
    $null = & git -C $Path init --quiet 2>&1
    if ($Email)
    {
        $null = & git -C $Path config user.email $Email 2>&1
    }

    return $Path
}

function New-ContributorTestWorkspace
{
    <#
        A workspace whose .memory-bank/projectbrief.md declares the given
        Knowledge areas, as bullets under "## Knowledge areas".
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)] [System.String] $Path,
        [Parameter()] [AllowEmptyCollection()] [System.String[]] $Area = @(),
        [Parameter()] [System.String[]] $ExtraLine = @()
    )

    $memoryBank = Join-Path -Path $Path -ChildPath '.memory-bank'
    $null = New-Item -ItemType Directory -Path $memoryBank -Force
    $lines = @('# Project brief', '', '## Overview', '', 'A workspace for tests.', '')
    if ($Area.Count -gt 0 -or $ExtraLine.Count -gt 0)
    {
        $lines += '## Knowledge areas'
        $lines += ''
        $lines += @($Area | ForEach-Object -Process { "- $_" })
        $lines += $ExtraLine
        $lines += ''
    }

    $lines += @('## Scope', '', '- Not an area: this bullet sits in another section.')
    [System.IO.File]::WriteAllText((Join-Path -Path $memoryBank -ChildPath 'projectbrief.md'), ($lines -join "`n"), [System.Text.UTF8Encoding]::new($false))
    return $Path
}
