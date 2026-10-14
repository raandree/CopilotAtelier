<#
.SYNOPSIS
    Measures the containment controls the specification completion workflow
    depends on and refuses the run when any of them is unproven.
.DESCRIPTION
    The /complete-specifications controller may not vouch for its own sandbox.
    This script is the external verifier its containment profile pins. It reads
    the profile as data, then measures the operating system: pinned control
    digests, whether the profile and the controls it pins are closed to the run,
    the remote-mutation hook's real exit codes, the absence of the
    remote override, egress policy, reachability, credential material, the
    writable filesystem set, and the ledger's protection.

    Three rules make the result meaningful.

    The profile is never evidence. Every claim it makes is checked against a
    measurement, and a check that cannot be measured is reported Unavailable,
    which fails the run exactly like an outright failure. A control that was not
    measured was not verified, and calling it passed would be the only kind of
    lie that matters here.

    Nothing is repaired. If a control is missing or weak the script says so and
    exits; silently fixing a containment boundary would destroy the evidence
    that it was broken.

    It measures a boundary but does not create one. Separate identities, a
    default-deny egress policy, and a filesystem policy that keeps the ledger
    out of the run's writable set are deployment work. On an ordinary developer
    workstation this script is expected to fail, and that failure is correct.
.PARAMETER Verify
    Runs the fixed verification set. This is the only supported operation.
.PARAMETER ProfilePath
    Containment profile to measure against.
.PARAMETER ProfileSha256
    Lowercase 64-hex digest of the profile, supplied by the operator as a direct
    argument. This is the trust anchor: it must arrive from outside the data the
    run can influence, so the verifier can detect a swapped profile.
.PARAMETER Role
    Identity being measured. Controller and worker have separate egress and
    writable-root expectations.
.PARAMETER LiveMode
    Live validation mode the caller intends to use. Anything other than off
    requires the live artifacts to be pinned in the profile.
.PARAMETER ReportPath
    Writes the structured result as JSON. Without it only the summary is shown.
.EXAMPLE
    Test-RunContainment.ps1 -Verify -ProfilePath D:\containment\profile.json -ProfileSha256 $digest -Role Controller
.NOTES
    Exit codes: 0 every check passed, 2 at least one check failed or could not
    be measured. There is no partial success.
#>

[CmdletBinding(DefaultParameterSetName = 'Verify')]
[OutputType([string])]
param(
    [Parameter(Mandatory, ParameterSetName = 'Verify')]
    [switch]$Verify,

    [Parameter(Mandatory, ParameterSetName = 'Verify')]
    [ValidateNotNullOrEmpty()]
    [string]$ProfilePath,

    [Parameter(Mandatory, ParameterSetName = 'Verify')]
    [ValidateNotNullOrEmpty()]
    [string]$ProfileSha256,

    [Parameter(Mandatory, ParameterSetName = 'Verify')]
    [ValidateSet('Controller', 'Worker')]
    [string]$Role,

    [Parameter(ParameterSetName = 'Verify')]
    [ValidateSet('off', 'read-only', 'disposable')]
    [string]$LiveMode = 'off',

    [Parameter(ParameterSetName = 'Verify')]
    [AllowEmptyString()]
    [string]$ReportPath
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$script:OnWindows = $IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop'
$script:OverrideName = 'COPILOT_ATELIER_ALLOW_REMOTE'
$script:PinnedControl = @('verifier', 'hooksConfig', 'hookScript', 'ledgerAppender')
$script:LiveControl = @('liveProfile', 'liveRunner', 'liveCommandTemplates')
$script:AllowedKey = @(
    'schemaVersion'
    'verifier'
    'hooksConfig'
    'hookScript'
    'ledgerAppender'
    'ledgerSink'
    'chainHead'
    'controllerEgressAllow'
    'workerEgressAllow'
    'controllerIdentity'
    'workerIdentity'
    'immutableControlPaths'
    'writableRoots'
) + $script:LiveControl

function New-CheckResult {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateSet('Pass', 'Fail', 'Unavailable')]
        [string]$Status,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Evidence
    )

    return [ordered]@{
        name = $Name
        status = $Status
        evidence = $Evidence
    }
}

function Get-Digest {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Resolve-WriteFailure {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $cause = $ErrorRecord.Exception.GetBaseException()

    if ($cause -is [System.UnauthorizedAccessException] -or $cause -is [System.Security.SecurityException]) {
        return @{ State = 'Denied'; Reason = 'access denied' }
    }

    return @{ State = 'Unknown'; Reason = $cause.Message }
}

function Get-WriteAccess {
    <#
        Opening for write without truncating proves the permission without
        changing a byte. Only an access denial proves a path is closed: a lock,
        a read-only attribute, or any other error leaves it unmeasured, and an
        unmeasured path must never read as protected.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (Test-Path -LiteralPath $Path -PathType Container) {
        $probe = Join-Path $Path ".containment-probe-$([guid]::NewGuid().ToString('N'))"
        try {
            [System.IO.File]::WriteAllText($probe, '')
        } catch {
            return (Resolve-WriteFailure -ErrorRecord $_)
        }

        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
        return @{ State = 'Writable'; Reason = 'accepted a new file' }
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return @{ State = 'Absent'; Reason = 'does not exist' }
    }

    if ($script:OnWindows -and ((Get-Item -LiteralPath $Path -Force).Attributes -band [System.IO.FileAttributes]::ReadOnly)) {
        return @{ State = 'Unknown'; Reason = 'the read-only attribute refuses the probe but is not an access control' }
    }

    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
    } catch {
        return (Resolve-WriteFailure -ErrorRecord $_)
    }

    $stream.Dispose()
    return @{ State = 'Writable'; Reason = 'opened for write' }
}

function Test-ProfileSchema {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        $ContainmentProfile
    )

    $problem = [System.Collections.Generic.List[string]]::new()
    $present = @($ContainmentProfile.PSObject.Properties.Name)

    foreach ($name in $present) {
        if ($name -notin $script:AllowedKey) {
            $problem.Add("unknown field '$name'")
        }
    }

    $required = @(
        'schemaVersion', 'verifier', 'hooksConfig', 'hookScript', 'ledgerAppender'
        'ledgerSink', 'chainHead', 'controllerEgressAllow', 'workerEgressAllow'
        'controllerIdentity', 'workerIdentity', 'immutableControlPaths', 'writableRoots'
    )

    foreach ($name in $required) {
        if ($name -notin $present) {
            $problem.Add("missing required field '$name'")
        }
    }

    foreach ($name in @('controllerEgressAllow', 'workerEgressAllow')) {
        if ($name -in $present) {
            $value = @($ContainmentProfile.$name)
            if ($value.Count -gt 0) {
                $problem.Add("'$name' must be empty; the controller and workers never reach a network")
            }
        }
    }

    foreach ($name in $script:PinnedControl) {
        if ($name -notin $present) {
            continue
        }

        $entry = $ContainmentProfile.$name
        $entryKey = @($entry.PSObject.Properties.Name)

        if ('path' -notin $entryKey -or 'sha256' -notin $entryKey) {
            $problem.Add("'$name' must declare a path and a sha256")
            continue
        }

        if ([string]$entry.sha256 -notmatch '^[0-9a-f]{64}$') {
            $problem.Add("'$name' declares a digest that is not lowercase 64-hex")
        }

        if ([string]$entry.path -match '[*?]') {
            $problem.Add("'$name' path contains a wildcard")
        }
    }

    foreach ($name in @('immutableControlPaths', 'writableRoots')) {
        if ($name -notin $present) {
            continue
        }

        foreach ($value in @($ContainmentProfile.$name)) {
            if ([string]$value -match '[*?]') {
                $problem.Add("'$name' contains a wildcard entry")
            }
        }
    }

    return $problem.ToArray()
}

function Invoke-HookPayload {
    <#
        The hook command is a full command line, so it runs through a throwaway
        shell script rather than being split into an executable and arguments;
        re-quoting it here is exactly how a probe stops matching the command the
        agent loop actually executes.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [string]$CommandLine,

        [Parameter(Mandatory)]
        [string]$Payload
    )

    $workRoot = Join-Path ([System.IO.Path]::GetTempPath()) "containment-hook-$([guid]::NewGuid().ToString('N'))"
    $null = New-Item -Path $workRoot -ItemType Directory -Force

    try {
        $payloadPath = Join-Path $workRoot 'payload.json'
        [System.IO.File]::WriteAllText($payloadPath, $Payload, [System.Text.UTF8Encoding]::new($false))

        if ($script:OnWindows) {
            $scriptPath = Join-Path $workRoot 'probe.cmd'
            [System.IO.File]::WriteAllText($scriptPath, "@echo off`r`n$CommandLine`r`n", [System.Text.ASCIIEncoding]::new())
            $process = Start-Process -FilePath $env:ComSpec -ArgumentList '/c', $scriptPath `
                -RedirectStandardInput $payloadPath -RedirectStandardOutput (Join-Path $workRoot 'out.txt') `
                -RedirectStandardError (Join-Path $workRoot 'err.txt') -Wait -PassThru -WindowStyle Hidden
        } else {
            $scriptPath = Join-Path $workRoot 'probe.sh'
            [System.IO.File]::WriteAllText($scriptPath, "#!/bin/sh`n$CommandLine`n", [System.Text.UTF8Encoding]::new($false))
            $process = Start-Process -FilePath '/bin/sh' -ArgumentList $scriptPath `
                -RedirectStandardInput $payloadPath -RedirectStandardOutput (Join-Path $workRoot 'out.txt') `
                -RedirectStandardError (Join-Path $workRoot 'err.txt') -Wait -PassThru
        }

        return [int]$process.ExitCode
    } finally {
        Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-HookContract {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$HookConfigPath
    )

    try {
        $configuration = Get-Content -LiteralPath $HookConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return New-CheckResult -Name 'HookContract' -Status 'Unavailable' -Evidence 'hooks.json is not valid JSON'
    }

    $preToolUse = @($configuration.hooks.PreToolUse)

    if ($preToolUse.Count -ne 1) {
        return New-CheckResult -Name 'HookContract' -Status 'Fail' -Evidence "expected exactly one PreToolUse hook, measured $($preToolUse.Count)"
    }

    $entry = $preToolUse[0]
    $commandLine = if ($script:OnWindows -and 'windows' -in @($entry.PSObject.Properties.Name)) {
        [string]$entry.windows
    } else {
        [string]$entry.command
    }

    if ([string]::IsNullOrWhiteSpace($commandLine)) {
        return New-CheckResult -Name 'HookContract' -Status 'Unavailable' -Evidence 'PreToolUse hook declares no command for this platform'
    }

    # Fixed synthetic payloads: one benign, one remote mutation, one issue
    # mutation. Nothing here is derived from the repository under test.
    $case = [ordered]@{
        safe = @{ expected = 0; payload = '{"tool_name":"read_file","tool_input":{"filePath":"README.md"}}' }
        push = @{ expected = 2; payload = '{"tool_name":"run_in_terminal","tool_input":{"command":"git push origin main"}}' }
        issue = @{ expected = 2; payload = '{"tool_name":"run_in_terminal","tool_input":{"command":"gh issue close 12"}}' }
    }

    $measured = [System.Collections.Generic.List[string]]::new()
    $failed = $false

    foreach ($name in $case.Keys) {
        try {
            $exitCode = Invoke-HookPayload -CommandLine $commandLine -Payload $case[$name].payload
        } catch {
            return New-CheckResult -Name 'HookContract' -Status 'Unavailable' -Evidence "could not run the $name payload: $($_.Exception.Message)"
        }

        $measured.Add("$name=$exitCode")

        if ($exitCode -ne $case[$name].expected) {
            $failed = $true
        }
    }

    $evidence = 'expected 0,2,2 and measured ' + ($measured -join ' ')

    if ($failed) {
        return New-CheckResult -Name 'HookContract' -Status 'Fail' -Evidence $evidence
    }

    return New-CheckResult -Name 'HookContract' -Status 'Pass' -Evidence $evidence
}

function Test-OverrideAbsent {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $set = [System.Collections.Generic.List[string]]::new()

    foreach ($scope in @('Process', 'User', 'Machine')) {
        try {
            $value = [Environment]::GetEnvironmentVariable($script:OverrideName, $scope)
        } catch {
            # User and Machine scopes do not exist off Windows.
            continue
        }

        if (-not [string]::IsNullOrEmpty($value)) {
            $set.Add($scope)
        }
    }

    # A fresh child proves the variable is not reintroduced by a profile or a
    # machine policy the parent process never saw.
    try {
        $child = & (Get-Process -Id $PID).Path -NoProfile -NonInteractive -Command "[Environment]::GetEnvironmentVariable('$($script:OverrideName)')"
        if (-not [string]::IsNullOrWhiteSpace(($child | Out-String).Trim())) {
            $set.Add('FreshProcess')
        }
    } catch {
        return New-CheckResult -Name 'OverrideAbsent' -Status 'Unavailable' -Evidence 'could not spawn a probe process'
    }

    if ($set.Count -gt 0) {
        return New-CheckResult -Name 'OverrideAbsent' -Status 'Fail' -Evidence ("$($script:OverrideName) is set in: " + ($set -join ', '))
    }

    return New-CheckResult -Name 'OverrideAbsent' -Status 'Pass' -Evidence "$($script:OverrideName) is unset in Process, User, Machine, and a fresh process"
}

function Test-EgressPolicy {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$DeclaredAllow
    )

    # An empty list binds as $null, and an empty allow set is the passing case.
    $allow = @($DeclaredAllow | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    if ($allow.Count -gt 0) {
        return New-CheckResult -Name 'EgressPolicy' -Status 'Fail' -Evidence "profile declares $($allow.Count) allowed destinations; this role must have none"
    }

    if (-not $script:OnWindows) {
        return New-CheckResult -Name 'EgressPolicy' -Status 'Unavailable' -Evidence 'outbound policy enumeration is implemented for Windows Defender Firewall only'
    }

    try {
        $firewallProfile = @(Get-FirewallProfileState)
    } catch {
        return New-CheckResult -Name 'EgressPolicy' -Status 'Unavailable' -Evidence "could not read the firewall profiles: $($_.Exception.Message)"
    }

    if ($firewallProfile.Count -eq 0) {
        return New-CheckResult -Name 'EgressPolicy' -Status 'Unavailable' -Evidence 'the firewall returned no profile, so the outbound default was not measured'
    }

    # A default of Block on a profile that is switched off enforces nothing, so
    # the enabled state is part of the measurement rather than an assumption.
    $disabled = [System.Collections.Generic.List[string]]::new()
    $permissive = [System.Collections.Generic.List[string]]::new()
    $unreadable = [System.Collections.Generic.List[string]]::new()

    foreach ($entry in $firewallProfile) {
        $name = Get-PropertyText -InputObject $entry -Name 'Name'

        if ([string]::IsNullOrWhiteSpace($name)) {
            $name = 'an unnamed profile'
        }

        $enabled = Get-PropertyText -InputObject $entry -Name 'Enabled'
        $action = Get-PropertyText -InputObject $entry -Name 'DefaultOutboundAction'

        if ($enabled -eq 'False') {
            $disabled.Add($name)
            continue
        }

        if ($enabled -ne 'True') {
            $unreadable.Add("$name reports Enabled='$enabled'")
            continue
        }

        if ([string]::IsNullOrWhiteSpace($action)) {
            $unreadable.Add("$name reports no DefaultOutboundAction")
            continue
        }

        if ($action -ne 'Block') {
            $permissive.Add("$name=$action")
        }
    }

    if ($disabled.Count -gt 0) {
        return New-CheckResult -Name 'EgressPolicy' -Status 'Fail' -Evidence ('the firewall profile is disabled, so its outbound default enforces nothing: ' + ($disabled -join ', '))
    }

    if ($permissive.Count -gt 0) {
        return New-CheckResult -Name 'EgressPolicy' -Status 'Fail' -Evidence ('outbound default is not Block: ' + ($permissive -join ', '))
    }

    if ($unreadable.Count -gt 0) {
        return New-CheckResult -Name 'EgressPolicy' -Status 'Unavailable' -Evidence ('the outbound policy was not measured: ' + ($unreadable -join ', '))
    }

    # A default-deny policy that allow-lists this identity is not a closed
    # egress policy, so the rules are enumerated rather than assumed absent.
    try {
        $allowRule = @(Get-OutboundAllowRule)
    } catch {
        return New-CheckResult -Name 'EgressPolicy' -Status 'Unavailable' -Evidence "could not read the outbound allow rules: $($_.Exception.Message)"
    }

    try {
        $callerSid = @(Get-CallerSecurityIdentifier)
    } catch {
        return New-CheckResult -Name 'EgressPolicy' -Status 'Unavailable' -Evidence "could not resolve the identity running the verifier: $($_.Exception.Message)"
    }

    if ($callerSid.Count -eq 0) {
        return New-CheckResult -Name 'EgressPolicy' -Status 'Unavailable' -Evidence 'the identity running the verifier resolved to no security identifier, so the allow rules were not evaluated'
    }

    $applicable = [System.Collections.Generic.List[string]]::new()

    foreach ($rule in $allowRule) {
        if (-not (Test-RuleAppliesToIdentity -LocalUser (Get-PropertyText -InputObject $rule -Name 'LocalUser') -SecurityIdentifier $callerSid)) {
            continue
        }

        $display = Get-PropertyText -InputObject $rule -Name 'DisplayName'

        if ([string]::IsNullOrWhiteSpace($display)) {
            $display = Get-PropertyText -InputObject $rule -Name 'Name'
        }

        $applicable.Add($display)
    }

    if ($applicable.Count -gt 0) {
        # Names, bounded: the evidence has to identify the hole without turning
        # a report into a dump of the whole rule set.
        $listed = @($applicable | Select-Object -First 10)
        $evidence = "$($applicable.Count) enabled outbound allow rules could apply to this identity: " + ($listed -join ', ')

        if ($applicable.Count -gt $listed.Count) {
            $evidence += " (and $($applicable.Count - $listed.Count) more)"
        }

        return New-CheckResult -Name 'EgressPolicy' -Status 'Fail' -Evidence $evidence
    }

    return New-CheckResult -Name 'EgressPolicy' -Status 'Pass' -Evidence "every firewall profile is enabled and defaults outbound traffic to Block, and none of $($allowRule.Count) enabled outbound allow rules applies to this identity; a system-wide proxy setting is not measured"
}

function Test-RemoteUnreachable {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    # Literal addresses, so a blocked DNS resolver cannot be mistaken for a
    # blocked network. An endpoint that answers at all, whether it accepts or
    # refuses, proves the packets left this machine.
    $canary = @(
        @{ Address = '1.1.1.1'; Port = 443 }
        @{ Address = '8.8.8.8'; Port = 53 }
    )

    # A probe that cannot connect to anything would report a closed network no
    # matter what the policy is, so it is validated against a listener this
    # process owns before a canary is attempted.
    $control = Invoke-ProbeSelfTest

    if (-not $control.Validated) {
        return New-CheckResult -Name 'RemoteUnreachable' -Status 'Unavailable' -Evidence "the probe could not be validated: $($control.Detail)"
    }

    $open = [System.Collections.Generic.List[string]]::new()
    $closed = [System.Collections.Generic.List[string]]::new()
    $unproven = [System.Collections.Generic.List[string]]::new()

    foreach ($target in $canary) {
        $endpoint = "$($target.Address):$($target.Port)"

        # Three seconds each, so the whole check stays under ten seconds with
        # the positive control included. A host that refuses slowly would
        # otherwise be read as unreachable, which costs a measurement.
        $outcome = Test-TcpEndpoint -Address $target.Address -Port $target.Port -TimeoutMilliseconds 3000

        switch ($outcome.Outcome) {
            'Connected' {
                $open.Add("$endpoint $($outcome.Detail)")
            }
            'Refused' {
                $open.Add("$endpoint $($outcome.Detail)")
            }
            'Denied' {
                $closed.Add($endpoint)
            }
            default {
                $unproven.Add("$endpoint $($outcome.Detail)")
            }
        }
    }

    if ($open.Count -gt 0) {
        return New-CheckResult -Name 'RemoteUnreachable' -Status 'Fail' -Evidence ('egress is open: ' + ($open -join '; '))
    }

    if ($unproven.Count -gt 0) {
        return New-CheckResult -Name 'RemoteUnreachable' -Status 'Unavailable' -Evidence ('not proven closed: ' + ($unproven -join '; ') + '; a network that is down cannot be told apart from one that is blocked')
    }

    return New-CheckResult -Name 'RemoteUnreachable' -Status 'Pass' -Evidence ('local policy denied the connection to ' + ($closed -join ', ') + ", and $($control.Detail)")
}

function Test-CredentialAbsence {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $variable = @('GH_TOKEN', 'GITHUB_TOKEN', 'HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'GIT_ASKPASS', 'SSH_AUTH_SOCK')
    $found = [System.Collections.Generic.List[string]]::new()

    foreach ($name in $variable) {
        if (-not [string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($name))) {
            $found.Add($name)
        }
    }

    $gitEvidence = 'git is not installed'
    $gitProblem = $null

    if (Get-Command -Name 'git' -CommandType Application -ErrorAction SilentlyContinue) {
        # The pattern also matches helpers scoped to one URL. git exits 1 when no
        # key matches, which is the clean case; any other non-zero exit means the
        # configuration was not read, which proves nothing.
        $previousPreference = $ErrorActionPreference
        $helper = @()
        $exitCode = $null

        try {
            $ErrorActionPreference = 'Continue'
            $helper = @(& git config --get-regexp '^credential\..*helper$' 2>$null)
            $exitCode = $LASTEXITCODE
        } catch {
            $gitProblem = "git config could not run: $($_.Exception.Message)"
        } finally {
            $ErrorActionPreference = $previousPreference
        }

        if ($null -eq $gitProblem) {
            if ($exitCode -eq 0) {
                foreach ($line in $helper) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$line)) {
                        $found.Add("git $line")
                    }
                }
            } elseif ($exitCode -eq 1) {
                $gitEvidence = 'git reports no credential helper, global or URL-scoped'
            } else {
                $gitProblem = "git config exited $exitCode, so its credential helpers were not read"
            }
        }
    }

    if ($found.Count -gt 0) {
        $evidence = 'credential or proxy material present: ' + ($found -join ', ')
        if ($gitProblem) {
            $evidence += "; $gitProblem"
        }

        return New-CheckResult -Name 'CredentialAbsence' -Status 'Fail' -Evidence $evidence
    }

    if ($gitProblem) {
        return New-CheckResult -Name 'CredentialAbsence' -Status 'Unavailable' -Evidence $gitProblem
    }

    return New-CheckResult -Name 'CredentialAbsence' -Status 'Pass' -Evidence ("none of $($variable -join ', ') is set, and $gitEvidence")
}

function Get-PropertyText {
    <#
        Reads one property as text without assuming it is there. A measurement
        that trips over a missing property is not a measurement, and under
        Set-StrictMode plain property access would do exactly that.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $InputObject,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($null -eq $InputObject) {
        return ''
    }

    $property = $InputObject.PSObject.Properties[$Name]

    if ($null -eq $property -or $null -eq $property.Value) {
        return ''
    }

    return [string]$property.Value
}

function Get-FirewallProfileState {
    <#
        Every firewall cmdlet call lives in one of these wrappers, so a test can
        replace the operating system without touching it, and so a missing
        module is one failure path instead of several. The active store is the
        effective policy, which is what a run is actually subject to.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param()

    if (-not (Get-Command -Name 'Get-NetFirewallProfile' -ErrorAction SilentlyContinue)) {
        throw 'Get-NetFirewallProfile is unavailable, so the outbound default cannot be measured'
    }

    return @(Get-NetFirewallProfile -PolicyStore 'ActiveStore' -ErrorAction Stop)
}

function Get-OutboundAllowRule {
    <#
        The enabled outbound allow rules of the active store, each carrying the
        user condition that decides whether it could apply to this run. The
        security filters are read once and joined on the rule identifier
        because the per-rule association is a separate call for every rule.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param()

    foreach ($name in @('Get-NetFirewallRule', 'Get-NetFirewallSecurityFilter')) {
        if (-not (Get-Command -Name $name -ErrorAction SilentlyContinue)) {
            throw "$name is unavailable, so the outbound allow rules cannot be measured"
        }
    }

    $rule = @(Get-NetFirewallRule -Direction 'Outbound' -Action 'Allow' -Enabled 'True' -PolicyStore 'ActiveStore' -ErrorAction Stop)
    $filter = @(Get-NetFirewallSecurityFilter -PolicyStore 'ActiveStore' -ErrorAction Stop)

    $userCondition = @{}

    foreach ($entry in $filter) {
        $key = Get-PropertyText -InputObject $entry -Name 'InstanceID'

        if (-not [string]::IsNullOrWhiteSpace($key)) {
            $userCondition[$key] = Get-PropertyText -InputObject $entry -Name 'LocalUser'
        }
    }

    return @($rule | ForEach-Object {
            $key = Get-PropertyText -InputObject $_ -Name 'InstanceID'

            [pscustomobject]@{
                Name = Get-PropertyText -InputObject $_ -Name 'Name'
                DisplayName = Get-PropertyText -InputObject $_ -Name 'DisplayName'
                LocalUser = if ($userCondition.ContainsKey($key)) { $userCondition[$key] } else { '' }
            }
        })
}

function Get-CallerSecurityIdentifier {
    <#
        The security identifiers of the identity running the verifier: its own
        and every group in its token, because a rule scoped to a group applies
        to every member of it.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $sid = [System.Collections.Generic.List[string]]::new()

    if ($null -ne $identity.User) {
        $sid.Add($identity.User.Value)
    }

    foreach ($group in @($identity.Groups)) {
        if ($null -ne $group) {
            $sid.Add($group.Value)
        }
    }

    return $sid.ToArray()
}

function Test-RuleAppliesToIdentity {
    <#
        Decides whether one outbound allow rule could apply to this run.

        What is evaluated: the rule's LocalUser condition. An absent or 'Any'
        condition applies to everyone. A condition that denies one of the
        caller's identifiers does not apply to it; one that allows any of them
        does; one that names only other principals does not. A condition that
        cannot be parsed applies, because an unread condition never proves a
        rule harmless.

        What is not evaluated, and is therefore treated as applying: the
        RemoteUser and RemoteMachine conditions, the program, service, port,
        address and interface scoping of the rule, the profile it is bound to,
        and the order in which Windows would evaluate several rules. A
        system-wide proxy is not measured at all, by this function or any other.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$LocalUser,

        [Parameter(Mandatory)]
        [string[]]$SecurityIdentifier
    )

    if ([string]::IsNullOrWhiteSpace($LocalUser) -or $LocalUser -eq 'Any') {
        return $true
    }

    # One SDDL access control entry: (type;flags;rights;objectGuid;inheritGuid;sid).
    $ace = [regex]::Matches($LocalUser, '\((?<type>[A-Z]+);[^;]*;[^;]*;[^;]*;[^;]*;(?<sid>[^;)]+)\)')

    if ($ace.Count -eq 0) {
        return $true
    }

    $known = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($value in $SecurityIdentifier) {
        $null = $known.Add($value)
    }

    $allowsCaller = $false

    foreach ($entry in $ace) {
        $sid = $entry.Groups['sid'].Value.Trim()

        if (-not $known.Contains($sid)) {
            continue
        }

        if ($entry.Groups['type'].Value -like 'D*') {
            return $false
        }

        $allowsCaller = $true
    }

    return $allowsCaller
}

function Test-TcpEndpoint {
    <#
        Classifies one connection attempt by what the socket reports. Only a
        denial by local policy proves an endpoint is closed to this run: a
        timeout or an unreachable network is indistinguishable from a network
        that is simply switched off, and a refusal proves the opposite of a
        closed egress, because something answered.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$Address,

        [Parameter(Mandatory)]
        [int]$Port,

        [Parameter()]
        [int]$TimeoutMilliseconds = 2000
    )

    $client = [System.Net.Sockets.TcpClient]::new()

    try {
        if (-not $client.ConnectAsync($Address, $Port).Wait($TimeoutMilliseconds)) {
            return @{ Outcome = 'Unreachable'; Detail = "timed out after $TimeoutMilliseconds ms" }
        }

        if ($client.Connected) {
            return @{ Outcome = 'Connected'; Detail = 'accepted the connection' }
        }

        return @{ Outcome = 'Unreachable'; Detail = 'ended without a connection and without an error' }
    } catch {
        $cause = $_.Exception.GetBaseException()
        $socketError = $null

        if ($cause -is [System.Net.Sockets.SocketException]) {
            $socketError = $cause.SocketErrorCode
        }

        switch ($socketError) {
            ([System.Net.Sockets.SocketError]::ConnectionRefused) {
                return @{ Outcome = 'Refused'; Detail = 'refused the connection, so it answered' }
            }
            ([System.Net.Sockets.SocketError]::AccessDenied) {
                return @{ Outcome = 'Denied'; Detail = 'was blocked by local policy' }
            }
            default {
                $reason = if ($null -eq $socketError) { $cause.Message } else { "$socketError" }
                return @{ Outcome = 'Unreachable'; Detail = "was not reached: $reason" }
            }
        }
    } finally {
        $client.Dispose()
    }
}

function Invoke-ProbeSelfTest {
    <#
        The positive control for the reachability check. It opens a listener on
        the loopback interface on a port the operating system picks, connects to
        it with the same function the canaries use, and closes it again. If this
        fails, the probe machinery is broken and a quiet network proves nothing.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [int]$TimeoutMilliseconds = 2000
    )

    $listener = $null

    try {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
        $listener.Start()
        $port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
    } catch {
        return @{ Validated = $false; Detail = "no loopback listener could be opened: $($_.Exception.Message)" }
    }

    try {
        $outcome = Test-TcpEndpoint -Address '127.0.0.1' -Port $port -TimeoutMilliseconds $TimeoutMilliseconds

        if ($outcome.Outcome -eq 'Connected') {
            return @{ Validated = $true; Detail = "the probe reached a loopback listener on port $port" }
        }

        return @{ Validated = $false; Detail = "the loopback listener on port $port $($outcome.Detail)" }
    } catch {
        return @{ Validated = $false; Detail = "the loopback probe failed: $($_.Exception.Message)" }
    } finally {
        $listener.Stop()

        if ($listener -is [System.IDisposable]) {
            $listener.Dispose()
        }
    }
}

function Test-WritableRoots {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$Declared
    )

    $root = @($Declared | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    if ($root.Count -eq 0) {
        return New-CheckResult -Name 'WritableRoots' -Status 'Fail' -Evidence 'profile declares no writable root'
    }

    $unwritable = [System.Collections.Generic.List[string]]::new()
    $unmeasured = [System.Collections.Generic.List[string]]::new()

    foreach ($declaredRoot in $root) {
        $access = Get-WriteAccess -Path $declaredRoot

        if ($access.State -eq 'Absent') {
            $unwritable.Add("$declaredRoot (absent)")
        } elseif ($access.State -eq 'Denied') {
            $unwritable.Add("$declaredRoot (not writable)")
        } elseif ($access.State -eq 'Unknown') {
            $unmeasured.Add("$declaredRoot ($($access.Reason))")
        }
    }

    # A bounded sample rather than a filesystem sweep: these are the roots whose
    # writability would let a run escape its worktree, so one hit is decisive.
    $forbidden = @(
        [Environment]::GetFolderPath('UserProfile')
        [System.IO.Path]::GetTempPath()
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    $escapable = [System.Collections.Generic.List[string]]::new()

    foreach ($forbiddenRoot in $forbidden) {
        $access = Get-WriteAccess -Path $forbiddenRoot

        if ($access.State -eq 'Writable') {
            $escapable.Add($forbiddenRoot)
        } elseif ($access.State -eq 'Unknown') {
            $unmeasured.Add("$forbiddenRoot ($($access.Reason))")
        }
    }

    if ($unwritable.Count -gt 0 -or $escapable.Count -gt 0) {
        $evidence = 'declared roots unusable: [' + ($unwritable -join '; ') + ']; writable outside the declared set: [' + ($escapable -join '; ') + ']'
        if ($unmeasured.Count -gt 0) {
            $evidence += '; not measurable: [' + ($unmeasured -join '; ') + ']'
        }

        return New-CheckResult -Name 'WritableRoots' -Status 'Fail' -Evidence $evidence
    }

    if ($unmeasured.Count -gt 0) {
        return New-CheckResult -Name 'WritableRoots' -Status 'Unavailable' -Evidence ('not measurable: ' + ($unmeasured -join '; '))
    }

    return New-CheckResult -Name 'WritableRoots' -Status 'Pass' -Evidence "declared roots are writable and the sampled roots outside them are not"
}

function Test-LedgerProtection {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$SinkPath,

        [Parameter(Mandatory)]
        [string]$ChainHeadPath
    )

    $writable = [System.Collections.Generic.List[string]]::new()
    $unmeasured = [System.Collections.Generic.List[string]]::new()

    foreach ($path in @($SinkPath, $ChainHeadPath)) {
        $access = Get-WriteAccess -Path $path

        if ($access.State -eq 'Writable') {
            $writable.Add($path)
        } elseif ($access.State -eq 'Unknown') {
            $unmeasured.Add("$path ($($access.Reason))")
        } elseif ($access.State -eq 'Absent') {
            # An absent record is only safe if the directory that would hold it
            # is closed to this identity; otherwise the run can create its own
            # ledger. A directory that does not exist yet cannot be measured.
            $directory = Split-Path -Parent $path

            if (-not $directory -or -not (Test-Path -LiteralPath $directory -PathType Container)) {
                $unmeasured.Add("$path (its directory does not exist, so its protection cannot be measured)")
            } else {
                $directoryAccess = Get-WriteAccess -Path $directory

                if ($directoryAccess.State -eq 'Writable') {
                    $writable.Add("$directory (would accept a substitute ledger)")
                } elseif ($directoryAccess.State -eq 'Unknown') {
                    $unmeasured.Add("$directory ($($directoryAccess.Reason))")
                }
            }
        }
    }

    if ($writable.Count -gt 0) {
        $evidence = 'writable by this identity: ' + ($writable -join '; ')
        if ($unmeasured.Count -gt 0) {
            $evidence += '; not measurable: ' + ($unmeasured -join '; ')
        }

        return New-CheckResult -Name 'LedgerProtection' -Status 'Fail' -Evidence $evidence
    }

    if ($unmeasured.Count -gt 0) {
        return New-CheckResult -Name 'LedgerProtection' -Status 'Unavailable' -Evidence ('not measurable: ' + ($unmeasured -join '; '))
    }

    return New-CheckResult -Name 'LedgerProtection' -Status 'Pass' -Evidence 'neither the sink nor the chain head is writable by this identity'
}

if (-not $Verify) {
    [Console]::Error.WriteLine('Containment verification requires -Verify.')
    exit 2
}

if ($ProfileSha256 -notmatch '^[0-9a-f]{64}$') {
    [Console]::Error.WriteLine('Containment refused: -ProfileSha256 must be a lowercase 64-hex digest.')
    exit 2
}

if (-not (Test-Path -LiteralPath $ProfilePath -PathType Leaf)) {
    [Console]::Error.WriteLine("Containment refused: profile '$ProfilePath' does not exist.")
    exit 2
}

$canonicalProfilePath = (Resolve-Path -LiteralPath $ProfilePath).ProviderPath
$measuredProfileDigest = Get-Digest -Path $canonicalProfilePath

if ($measuredProfileDigest -ne $ProfileSha256.ToLowerInvariant()) {
    [Console]::Error.WriteLine("Containment refused: profile digest $measuredProfileDigest does not match the direct argument.")
    exit 2
}

$check = [System.Collections.Generic.List[hashtable]]::new()
$check.Add((New-CheckResult -Name 'ProfileDigest' -Status 'Pass' -Evidence "profile matches the direct argument $measuredProfileDigest"))

try {
    $containmentProfile = Get-Content -LiteralPath $canonicalProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
    [Console]::Error.WriteLine('Containment refused: profile is not valid JSON.')
    exit 2
}

# Wrapped because an empty result unwraps to $null, and strict mode refuses
# .Count on it.
$schemaProblem = @(Test-ProfileSchema -ContainmentProfile $containmentProfile)

if ($schemaProblem.Count -gt 0) {
    $check.Add((New-CheckResult -Name 'ProfileSchema' -Status 'Fail' -Evidence ($schemaProblem -join '; ')))
} else {
    $check.Add((New-CheckResult -Name 'ProfileSchema' -Status 'Pass' -Evidence 'closed schema satisfied and both egress lists are empty'))
}

$profileKey = @($containmentProfile.PSObject.Properties.Name)
$digestProblem = [System.Collections.Generic.List[string]]::new()

foreach ($name in $script:PinnedControl) {
    if ($name -notin $profileKey) {
        $digestProblem.Add("$name is not declared")
        continue
    }

    $declaredPath = [string]$containmentProfile.$name.path

    if (-not (Test-Path -LiteralPath $declaredPath -PathType Leaf)) {
        $digestProblem.Add("$name path does not exist")
        continue
    }

    $canonical = (Resolve-Path -LiteralPath $declaredPath).ProviderPath
    $measured = Get-Digest -Path $canonical

    if ($measured -ne [string]$containmentProfile.$name.sha256) {
        $digestProblem.Add("$name digest is $measured but the profile pins $($containmentProfile.$name.sha256)")
    }
}

if ($digestProblem.Count -gt 0) {
    $check.Add((New-CheckResult -Name 'ControlDigest' -Status 'Fail' -Evidence ($digestProblem -join '; ')))
} else {
    $check.Add((New-CheckResult -Name 'ControlDigest' -Status 'Pass' -Evidence "every pinned control matches its declared digest"))
}

# The controller needs evidence that the profile and the controls it pins are
# closed to every run identity, so they are measured whether or not the profile
# lists them as immutable.
$immutableCandidate = [System.Collections.Generic.List[string]]::new()
$immutableCandidate.Add($canonicalProfilePath)

foreach ($name in $script:PinnedControl) {
    if ($name -notin $profileKey) {
        continue
    }

    $entry = $containmentProfile.$name

    if ($entry -is [System.Management.Automation.PSCustomObject] -and 'path' -in @($entry.PSObject.Properties.Name)) {
        $immutableCandidate.Add([string]$entry.path)
    }
}

if ('immutableControlPaths' -in $profileKey) {
    foreach ($path in @($containmentProfile.immutableControlPaths)) {
        $immutableCandidate.Add([string]$path)
    }
}

$pathComparer = if ($script:OnWindows) { [System.StringComparer]::OrdinalIgnoreCase } else { [System.StringComparer]::Ordinal }
$measuredPath = [System.Collections.Generic.HashSet[string]]::new($pathComparer)
$mutable = [System.Collections.Generic.List[string]]::new()
$unmeasured = [System.Collections.Generic.List[string]]::new()

foreach ($path in $immutableCandidate) {
    if ([string]::IsNullOrWhiteSpace($path)) {
        continue
    }

    try {
        $pathKey = [System.IO.Path]::GetFullPath($path)
    } catch {
        $pathKey = $path
    }

    if (-not $measuredPath.Add($pathKey)) {
        continue
    }

    $access = Get-WriteAccess -Path $path

    if ($access.State -eq 'Writable') {
        $mutable.Add($path)
    } elseif ($access.State -eq 'Absent') {
        $mutable.Add("$path (does not exist)")
    } elseif ($access.State -eq 'Unknown') {
        $unmeasured.Add("$path ($($access.Reason))")
    }
}

if ($mutable.Count -gt 0) {
    $evidence = 'writable by this identity or missing: ' + ($mutable -join '; ')
    if ($unmeasured.Count -gt 0) {
        $evidence += '; not measurable: ' + ($unmeasured -join '; ')
    }

    $check.Add((New-CheckResult -Name 'ControlImmutability' -Status 'Fail' -Evidence $evidence))
} elseif ($unmeasured.Count -gt 0) {
    $check.Add((New-CheckResult -Name 'ControlImmutability' -Status 'Unavailable' -Evidence ('not measurable: ' + ($unmeasured -join '; '))))
} else {
    $check.Add((New-CheckResult -Name 'ControlImmutability' -Status 'Pass' -Evidence 'the profile, every pinned control, and every declared immutable path are closed to this identity'))
}

if ('hooksConfig' -in $profileKey -and (Test-Path -LiteralPath ([string]$containmentProfile.hooksConfig.path) -PathType Leaf)) {
    $check.Add((Test-HookContract -HookConfigPath ([string]$containmentProfile.hooksConfig.path)))
} else {
    $check.Add((New-CheckResult -Name 'HookContract' -Status 'Unavailable' -Evidence 'no readable hooks.json to exercise'))
}

$check.Add((Test-OverrideAbsent))

$declaredAllow = if ($Role -eq 'Controller') {
    @($containmentProfile.controllerEgressAllow)
} else {
    @($containmentProfile.workerEgressAllow)
}

$check.Add((Test-EgressPolicy -DeclaredAllow ([string[]]$declaredAllow)))
$check.Add((Test-RemoteUnreachable))
$check.Add((Test-CredentialAbsence))
$check.Add((Test-WritableRoots -Declared ([string[]]@($containmentProfile.writableRoots))))
$check.Add((Test-LedgerProtection -SinkPath ([string]$containmentProfile.ledgerSink) -ChainHeadPath ([string]$containmentProfile.chainHead)))

if ($LiveMode -ne 'off') {
    $liveProblem = [System.Collections.Generic.List[string]]::new()

    foreach ($name in $script:LiveControl) {
        if ($name -notin $profileKey) {
            $liveProblem.Add("live mode '$LiveMode' requires '$name' to be pinned in the profile")
            continue
        }

        $declaredPath = [string]$containmentProfile.$name.path

        if (-not (Test-Path -LiteralPath $declaredPath -PathType Leaf)) {
            $liveProblem.Add("live artifact '$name' does not exist")
            continue
        }

        if ((Get-Digest -Path $declaredPath) -ne [string]$containmentProfile.$name.sha256) {
            $liveProblem.Add("live artifact '$name' does not match its declared digest")
        }
    }

    if ($liveProblem.Count -gt 0) {
        $check.Add((New-CheckResult -Name 'LiveArtifacts' -Status 'Fail' -Evidence ($liveProblem -join '; ')))
    } else {
        $check.Add((New-CheckResult -Name 'LiveArtifacts' -Status 'Pass' -Evidence "live artifacts are pinned and match for mode '$LiveMode'"))
    }
}

# Unavailable is not a lesser failure. A control that could not be measured was
# not verified, and the run must stop for it exactly as for a measured breach.
$blocking = @($check | Where-Object { $_.status -ne 'Pass' })
$verdict = if ($blocking.Count -eq 0) { 'Pass' } else { 'Fail' }

$report = [ordered]@{
    verdict = $verdict
    role = $Role
    liveMode = $LiveMode
    profilePath = $canonicalProfilePath
    profileSha256 = $measuredProfileDigest
    measuredUtc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    checks = @($check)
}

if (-not [string]::IsNullOrWhiteSpace($ReportPath)) {
    $reportDirectory = Split-Path -Parent $ReportPath

    if ($reportDirectory -and -not (Test-Path -LiteralPath $reportDirectory)) {
        $null = New-Item -Path $reportDirectory -ItemType Directory -Force
    }

    $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
}

foreach ($result in $blocking) {
    [Console]::Error.WriteLine("Containment $($result.status): $($result.name) - $($result.evidence)")
}

if ($verdict -eq 'Pass') {
    Write-Output "Containment verified for $Role with $($check.Count) checks passed."
    exit 0
}

Write-Output "Containment NOT verified for ${Role}: $($blocking.Count) of $($check.Count) checks did not pass."
exit 2
