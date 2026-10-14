<#
.SYNOPSIS
    Measures the containment controls the specification completion workflow
    depends on, revalidates its sealed ledger, and refuses the run when any of
    them is unproven.
.DESCRIPTION
    The /complete-specifications controller may not vouch for its own sandbox.
    This script is the external verifier its containment profile pins. It reads
    the profile as data, then measures the operating system.

    -Verify measures: that the verifier that runs is the pinned file; the pinned
    control digests; whether the profile and every control it pins are closed to
    the run, with the directories above them; that the verifier runs as the
    identity the profile declares for the role; the remote-mutation hook's real
    exit codes, run only on controls already measured and through an interpreter
    named by absolute path that the run cannot replace; that no hook that
    records a Remote grant is registered in the pinned hooks.json and none is
    waiting; egress policy; reachability; credential material; that each
    declared writable root is writable and a named escape set is not; and the
    ledger's protection. It does not enumerate the filesystem.

    -Revalidate runs the pinned appender's profile-bound validation of the sealed
    ledger, again only on controls already measured, and checks that the ledger
    records the digest of the final report.

    It runs only as the entry script of a process of its own, and refuses a
    launch that does not look like one: the command line must name this script
    after -File with -NoProfile before it, and the script must be the only
    frame of the call stack, because a function or a type defined earlier in a
    session outranks the ones it measures with. That reads the launch. Code that
    already runs inside the process, such as a .NET startup hook named by
    DOTNET_STARTUP_HOOKS, cannot be seen from inside, and the firewall cmdlets
    are resolved by name, so the module search path is inherited: the
    environment belongs to whatever starts the verifier.

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
    Runs the fixed verification set.
.PARAMETER Revalidate
    Revalidates the sealed ledger and the final report instead.
.PARAMETER ProfilePath
    Containment profile to measure against.
.PARAMETER ProfileSha256
    Lowercase 64-hex digest of the profile, supplied by the operator as a direct
    argument and compared exactly as written. This is the trust anchor: it must
    arrive from outside the data the run can influence, so the verifier can
    detect a swapped profile.
.PARAMETER Role
    Identity being measured. The verifier must run as the identity the profile
    declares for this role.
.PARAMETER LiveMode
    Live validation mode the caller intends to use. Anything other than off
    requires the live artifacts to be pinned in the profile.
.PARAMETER FinalReportPath
    Absolute path of the final report to revalidate against the sealed ledger.
.PARAMETER ReportPath
    Writes the structured result as JSON. Without it only the summary is shown.
    It must be an absolute path in a directory that already exists, and it must
    not be, or lie inside, any file the verdict depends on. A stream of such a
    file, a device or extended-length spelling of it, and on Windows a path
    through a junction or a symbolic link are refused too.
.EXAMPLE
    pwsh -NoProfile -NonInteractive -File Test-RunContainment.ps1 -Verify -ProfilePath D:\containment\profile.json -ProfileSha256 $digest -Role Controller
.EXAMPLE
    pwsh -NoProfile -NonInteractive -File Test-RunContainment.ps1 -Revalidate -ProfilePath D:\containment\profile.json -ProfileSha256 $digest -Role Controller -FinalReportPath D:\run\final-report.md
.NOTES
    Exit codes: 0 every check passed, 2 at least one check failed or could not
    be measured, or the call was refused. There is no partial success. Any other
    exit code, including 1 from an unhandled error, means the verifier itself
    failed, and nothing was verified.
#>

[CmdletBinding(DefaultParameterSetName = 'Verify')]
[OutputType([string])]
param(
    [Parameter(Mandatory, ParameterSetName = 'Verify')]
    [switch]$Verify,

    [Parameter(Mandatory, ParameterSetName = 'Revalidate')]
    [switch]$Revalidate,

    [Parameter(Mandatory, ParameterSetName = 'Verify')]
    [Parameter(Mandatory, ParameterSetName = 'Revalidate')]
    [ValidateNotNullOrEmpty()]
    [string]$ProfilePath,

    [Parameter(Mandatory, ParameterSetName = 'Verify')]
    [Parameter(Mandatory, ParameterSetName = 'Revalidate')]
    [ValidateNotNullOrEmpty()]
    [string]$ProfileSha256,

    [Parameter(Mandatory, ParameterSetName = 'Verify')]
    [Parameter(Mandatory, ParameterSetName = 'Revalidate')]
    [ValidateSet('Controller', 'Worker')]
    [string]$Role,

    [Parameter(ParameterSetName = 'Verify')]
    [ValidateSet('off', 'read-only', 'disposable')]
    [string]$LiveMode = 'off',

    [Parameter(Mandatory, ParameterSetName = 'Revalidate')]
    [ValidateNotNullOrEmpty()]
    [string]$FinalReportPath,

    [Parameter(ParameterSetName = 'Verify')]
    [Parameter(ParameterSetName = 'Revalidate')]
    [AllowEmptyString()]
    [string]$ReportPath
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$script:OnWindows = $IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop'
$script:PinnedControl = @('verifier', 'hooksConfig', 'hookScript', 'ledgerAppender')
$script:LiveControl = @('liveProfile', 'liveRunner', 'liveCommandTemplates')
$script:RightName = @('WriteData', 'AppendData', 'DeleteChild', 'Delete', 'WriteDac', 'WriteOwner')
# One access mask means a different right on a file and on a directory: the first label applies to
# a file, the second to a directory.
$script:RightLabel = @{
    WriteData = @('FILE_WRITE_DATA', 'FILE_ADD_FILE')
    AppendData = @('FILE_APPEND_DATA', 'FILE_ADD_SUBDIRECTORY')
    DeleteChild = @('FILE_DELETE_CHILD', 'FILE_DELETE_CHILD')
    Delete = @('DELETE', 'DELETE')
    WriteDac = @('WRITE_DAC', 'WRITE_DAC')
    WriteOwner = @('WRITE_OWNER', 'WRITE_OWNER')
}
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
# Names read from a document are compared exactly. -in and -notin compare by culture, and a culture
# ignores characters such as a zero-width space, so a name that only looks like a known one would pass.
$script:AllowedKeySet = [System.Collections.Generic.HashSet[string]]::new([string[]]$script:AllowedKey, [System.StringComparer]::Ordinal)
# The keys a host reads a command from, and the whole set of keys the guard's hook entry may carry.
$script:CommandKey = @('command', 'windows', 'powershell', 'bash', 'linux', 'osx')
$script:EntryKeySet = [System.Collections.Generic.HashSet[string]]::new([string[]](@('type', 'timeout') + $script:CommandKey), [System.StringComparer]::Ordinal)
# The one statement the shipped Windows hook command ends with, after a semicolon, for the PowerShell a host
# wraps it in: it makes that wrapper exit with the code of the command. Nothing else may follow a semicolon.
$script:HookExitTail = 'exit (@(Get-Variable -Name LASTEXITCODE -ValueOnly -ErrorAction Ignore) + 2)[0]'

function New-CheckResult {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds an in-memory result object and changes no system state.')]
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
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

function Get-PowerShellLaunchOption {
    <#
        Reads the options of a PowerShell command line, in order, up to the script or the command, and
        says whether they can be trusted. Only options that cannot change what runs before the script
        are allowed: -NoProfile, -NonInteractive, -NoLogo, -ExecutionPolicy, -WindowStyle,
        -WorkingDirectory, -MTA and -STA. Anything else is refused, because an option such as
        -ConfigurationFile or -SettingsFile applies code or a module path before the first line of the
        script, and so is an argument that is not an option at all.

        An option that takes a value takes the next argument whatever it looks like, as PowerShell does:
        "-WorkingDirectory -nop" is a directory named -nop and no -NoProfile. -File, -Command and
        -EncodedCommand end the scan, since everything after them belongs to the script or the command.

        The result is a hashtable with Problem (text, or nothing), StopKind (File, Command,
        EncodedCommand, or empty when the line ended first), StopIndex and NoProfile (whether -NoProfile
        came before the stop).

        This runs inside the check that decides whether the process can be trusted at all, so it uses
        operators and .NET members only: a command a session redefined, such as an alias that outranks
        a function, must not be on its path.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Argument
    )

    $ordinal = [System.StringComparison]::Ordinal
    $flag = [System.Collections.Generic.HashSet[string]]::new([string[]]@('noni', 'noninteractive', 'nol', 'nologo', 'mta', 'sta'), [System.StringComparer]::Ordinal)
    $valued = [System.Collections.Generic.HashSet[string]]::new([string[]]@('ex', 'ep', 'executionpolicy', 'w', 'windowstyle', 'wd', 'workingdirectory'), [System.StringComparer]::Ordinal)
    $result = @{ Problem = $null; StopKind = ''; StopIndex = -1; NoProfile = $false }
    $index = 0

    while ($index -lt $Argument.Count) {
        $token = $Argument[$index]
        $shown = [regex]::Replace($token, '[^\x20-\x7E]', '?')

        if ($shown.Length -gt 40) {
            $shown = $shown.Substring(0, 40) + '...'
        }

        if ($token -notmatch '^[-/](?<name>[A-Za-z]+)$') {
            $result.Problem = "the argument '$shown' comes before the script or command and is not an option"
            return $result
        }

        $name = $Matches['name'].ToLowerInvariant()

        if ('file'.StartsWith($name, $ordinal)) {
            $result.StopKind = 'File'
            $result.StopIndex = $index
            return $result
        }

        if ('command'.StartsWith($name, $ordinal)) {
            $result.StopKind = 'Command'
            $result.StopIndex = $index
            return $result
        }

        if ('encodedcommand'.StartsWith($name, $ordinal) -or [string]::Equals($name, 'ec', $ordinal)) {
            $result.StopKind = 'EncodedCommand'
            $result.StopIndex = $index
            return $result
        }

        if ($name.Length -ge 3 -and 'noprofile'.StartsWith($name, $ordinal)) {
            $result.NoProfile = $true
            $index++
            continue
        }

        if ($flag.Contains($name)) {
            $index++
            continue
        }

        if ($valued.Contains($name)) {
            if ($index + 1 -ge $Argument.Count) {
                $result.Problem = "the option '$shown' takes a value and has none"
                return $result
            }

            $index += 2
            continue
        }

        $result.Problem = "the option '$shown' is not one this check allows before the script or command; only -NoProfile, -NonInteractive, -NoLogo, -ExecutionPolicy, -WindowStyle, -WorkingDirectory, -MTA and -STA are"
        return $result
    }

    return $result
}

function Get-FreshProcessProblem {
    <#
        Why this process cannot be trusted to run the functions and types this script means, or
        nothing when it can. A name a script calls is looked up in the session before it is looked
        up in a module, so a function a caller defined, or a type it declared, outranks the one this
        script uses; code that ran earlier in the same session can make every measurement read as
        it likes. The verifier therefore runs only as the entry script of a process of its own:
        -File names it, so nothing ran before it that the person who started the process did not
        choose, and -NoProfile keeps the profile of the user out of the session.

        The arguments are the command line of the process, whose first element is the host. The
        options before -File are read by Get-PowerShellLaunchOption: only options that cannot change
        what runs first are allowed, so -ConfigurationFile and -SettingsFile, which do, are refused.
        Everything after -File belongs to the script and does not count.

        A command line is not enough on its own: -Command takes every argument after it as command
        text, yet the host still lists them, so "-Command <code> -File <script>" reads exactly like
        "-File <script>" and the code runs first. What tells them apart is the call stack where the
        script starts. Under -File the script is its one frame; code that ran around it adds another.
        What this cannot see is code that already runs inside this process before its first line,
        such as a .NET startup hook named by the environment: only the launcher can stop that.

        This is the check that decides whether anything else in the script can be believed, so it
        and the option reader use operators and .NET members only and are called through the function
        table, never by name. Command lookup tries an alias before a function, so a session that
        aliased the name of this check made the call do nothing and the launch skip it.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$CommandLineArgument,

        [Parameter(Mandatory)]
        [string]$ScriptPath,

        [Parameter(Mandatory)]
        [int]$CallStackDepth
    )

    $remedy = 'start it as: pwsh -NoProfile -NonInteractive -File <this script> ...'
    $notFresh = "this is not a fresh process that was started with -File naming this script, and a function or type defined earlier in the session outranks the ones the script uses; $remedy"
    $argument = [string[]]::new([Math]::Max($CommandLineArgument.Count - 1, 0))

    for ($index = 1; $index -lt $CommandLineArgument.Count; $index++) {
        $argument[$index - 1] = $CommandLineArgument[$index]
    }

    $scan = & ${function:Get-PowerShellLaunchOption} -Argument $argument

    if ($null -ne $scan.Problem) {
        return "this is not a fresh process: $($scan.Problem), and a function or type defined by what that option loads outranks the ones the script uses; $remedy"
    }

    if (-not [string]::Equals([string]$scan.StopKind, 'File', [System.StringComparison]::Ordinal) -or $scan.StopIndex + 1 -ge $argument.Count) {
        return $notFresh
    }

    $comparison = if ([System.IO.Path]::DirectorySeparatorChar -eq [char]92) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }

    try {
        $named = [System.IO.Path]::GetFullPath($argument[$scan.StopIndex + 1])
        $own = [System.IO.Path]::GetFullPath($ScriptPath)
    } catch {
        return $notFresh
    }

    if (-not $named.Equals($own, $comparison)) {
        return $notFresh
    }

    if ($CallStackDepth -ne 1) {
        return "other code ran around this script (its call stack holds $CallStackDepth frames, not one), so this is not a fresh process whose first act is this script, and a function or type defined by that code outranks the ones this script uses; $remedy"
    }

    if (-not $scan.NoProfile) {
        return "the process loaded the profile of the user, which can define functions that outrank the ones this script uses; $remedy"
    }

    return $null
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

function Initialize-NativeAccess {
    <#
        Windows only. Defines a one-call wrapper over CreateFileW that asks for exactly one access
        right and nothing else: no read, no write, no truncation. The call succeeds precisely when
        the access check grants the right, and closing the handle changes nothing on disk, so the
        right is measured and never exercised. Backup semantics let it open a directory, and the
        open does not follow a link.

        The type is defined under a name made for this process alone and is held in
        $script:NativeProbe, and it is never looked up by a fixed name: a type of a fixed name that
        something declared earlier in the session would otherwise be the one that answers every probe.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    $existing = Get-Variable -Name NativeProbe -Scope Script -ValueOnly -ErrorAction SilentlyContinue

    if ($null -ne $existing) {
        return
    }

    $typeName = 'ContainmentNative' + [guid]::NewGuid().ToString('N')

    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public static class $typeName
{
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern SafeFileHandle CreateFileW(string fileName, uint desiredAccess, uint shareMode, IntPtr securityAttributes, uint creationDisposition, uint flagsAndAttributes, IntPtr templateFile);

    // 0 when the access check grants the right, otherwise the Win32 error code.
    public static int Probe(string path, uint access)
    {
        using (SafeFileHandle handle = CreateFileW(path, access, 7u, IntPtr.Zero, 3u, 0x02200000u, IntPtr.Zero))
        {
            return handle.IsInvalid ? Marshal.GetLastWin32Error() : 0;
        }
    }
}
"@

    $script:NativeProbe = $typeName -as [type]
}

function Get-PathChain {
    <#
        The canonical absolute path, then each of its ancestors up to the root. A path is judged
        together with every directory above it, because a directory that lets the caller delete or
        rewrite its children lets the caller replace the path whatever the file itself says.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $current = [System.IO.Path]::TrimEndingDirectorySeparator([System.IO.Path]::GetFullPath($Path))
    $chain = [System.Collections.Generic.List[string]]::new()
    $chain.Add($current)

    while ($true) {
        $parent = [System.IO.Path]::GetDirectoryName($current)

        if ([string]::IsNullOrEmpty($parent) -or [string]::Equals($parent, $current, [System.StringComparison]::Ordinal)) {
            break
        }

        $chain.Add($parent)
        $current = $parent
    }

    return $chain.ToArray()
}

function Test-PathOverlap {
    <#
        True when the path equals a writable root, lies inside one, or contains one. A protected path
        inside a root the run may write is not protected, and a protected directory that holds a
        writable root is not closed.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$WritableRoot
    )

    $comparison = if ($script:OnWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    $separator = [string][System.IO.Path]::DirectorySeparatorChar
    $subject = [System.IO.Path]::TrimEndingDirectorySeparator([System.IO.Path]::GetFullPath($Path))
    $subjectPrefix = if ($subject.EndsWith($separator, $comparison)) { $subject } else { $subject + $separator }

    foreach ($root in @($WritableRoot | Where-Object -FilterScript { -not [string]::IsNullOrWhiteSpace($_) })) {
        $candidate = [System.IO.Path]::TrimEndingDirectorySeparator([System.IO.Path]::GetFullPath($root))
        $candidatePrefix = if ($candidate.EndsWith($separator, $comparison)) { $candidate } else { $candidate + $separator }

        if ($subject.Equals($candidate, $comparison) -or
            $subject.StartsWith($candidatePrefix, $comparison) -or
            $candidate.StartsWith($subjectPrefix, $comparison)) {
            return $true
        }
    }

    return $false
}

function Get-ObjectRight {
    <#
        What this identity can do to one object, measured without changing it: for each right that
        lets a run replace or loosen a protected path, Granted, Denied, or Unknown. Only an access
        denial proves a right closed, and a sharing violation shows it was granted. Any other failure
        leaves it Unknown, and an unknown right never reads as protected.

        On Windows each right is asked of the kernel with its own open (Initialize-NativeAccess), so
        group membership, deny entries, inheritance, and ownership are all resolved by the operating
        system and not by this script: the owner of an object always holds WRITE_DAC, whatever a deny
        entry says. A read-only attribute refuses every write open whatever the access list says, so
        a refused write on a read-only file is Denied only when the attribute itself cannot be
        cleared, and Unknown otherwise. Elsewhere only write access is measured.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $right = @{}
    foreach ($name in $script:RightName) {
        $right[$name] = 'Unknown'
    }

    $result = [pscustomobject]@{
        Path = $Path
        State = 'Unknown'
        IsDirectory = $false
        IsReparsePoint = $false
        ReadOnly = $false
        Right = $right
        Reason = ''
    }

    try {
        $attribute = [System.IO.File]::GetAttributes($Path)
    } catch [System.IO.FileNotFoundException], [System.IO.DirectoryNotFoundException] {
        $result.State = 'Absent'
        $result.Reason = 'does not exist'
        return $result
    } catch {
        $result.Reason = $_.Exception.GetBaseException().Message
        return $result
    }

    $result.IsDirectory = [bool]($attribute -band [System.IO.FileAttributes]::Directory)
    $result.IsReparsePoint = [bool]($attribute -band [System.IO.FileAttributes]::ReparsePoint)
    $result.ReadOnly = [bool]($attribute -band [System.IO.FileAttributes]::ReadOnly)

    if (-not $script:OnWindows) {
        $access = Get-WriteAccess -Path $Path
        $state = switch ($access.State) {
            'Writable' { 'Granted' }
            'Denied' { 'Denied' }
            default { 'Unknown' }
        }

        $right['WriteData'] = $state
        $right['AppendData'] = $state
        $right['DeleteChild'] = if ($result.IsDirectory) { $state } else { 'Denied' }
        $result.Reason = 'only write access is measured on this platform; deletion, ownership, and permission changes are not'
        $result.State = 'Measured'
        return $result
    }

    try {
        Initialize-NativeAccess
    } catch {
        $result.Reason = "the native access probe could not be defined, so no right was measured: $($_.Exception.Message)"
        return $result
    }

    $mask = [ordered]@{ WriteData = 0x2; AppendData = 0x4; DeleteChild = 0x40; Delete = 0x10000; WriteDac = 0x40000; WriteOwner = 0x80000 }
    $problem = [System.Collections.Generic.List[string]]::new()
    $attributeCode = $null

    if ($result.ReadOnly -and -not $result.IsDirectory) {
        $attributeCode = $script:NativeProbe::Probe($Path, [uint32]0x100)
    }

    foreach ($name in $mask.Keys) {
        if ($name -eq 'DeleteChild' -and -not $result.IsDirectory) {
            $right[$name] = 'Denied'
            continue
        }

        $code = $script:NativeProbe::Probe($Path, [uint32]$mask[$name])

        if ($code -eq 0) {
            $right[$name] = 'Granted'
        } elseif ($code -eq 5) {
            if ($result.ReadOnly -and $name -in @('WriteData', 'AppendData')) {
                $right[$name] = if ($attributeCode -eq 5) { 'Denied' } else { 'Unknown' }
            } else {
                $right[$name] = 'Denied'
            }
        } elseif ($code -eq 32) {
            # ERROR_SHARING_VIOLATION. The kernel checks the access list before it compares share
            # modes: a right the list denies still returns 5 while another handle holds the file
            # (measured with a held file and a deny entry), so 32 means the list granted the right
            # and only that handle's sharing blocked this open. The live appender holds the ledger
            # sink open for appending for the whole run, and the sink must stay measurable.
            $right[$name] = 'Granted'
        } else {
            $problem.Add("$name (Win32 error $code)")
        }
    }

    $result.Reason = $problem -join '; '
    $result.State = 'Measured'
    return $result
}

function Test-PathProtection {
    <#
        Whether a path is closed to this identity: the object itself, the directory that holds it, and
        every directory above it. A file is replaceable by whoever can delete it, whoever can delete
        children of its directory, and whoever can rewrite an access list or the owner on the way, so
        a file that is merely not writable is not protected. A path that does not exist yet is closed
        only if nothing on the way lets this identity create it. A reparse point on the way means the
        path does not name the object it protects. A right that could not be measured is reported
        apart from a measured breach and never counts as closed.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$WritableRoot = @()
    )

    $violation = [System.Collections.Generic.List[string]]::new()
    $unmeasured = [System.Collections.Generic.List[string]]::new()
    $chain = @(Get-PathChain -Path $Path)
    $object = @($chain | ForEach-Object -Process { Get-ObjectRight -Path $_ })
    $leafAbsent = $object[0].State -eq 'Absent'
    $firstExisting = -1

    for ($index = 0; $index -lt $object.Count; $index++) {
        if ($object[$index].State -ne 'Absent') {
            $firstExisting = $index
            break
        }
    }

    if ($firstExisting -lt 0) {
        $unmeasured.Add("${Path}: no part of the path exists, so nothing on it could be measured")
    }

    for ($index = [Math]::Max($firstExisting, 0); $firstExisting -ge 0 -and $index -lt $object.Count; $index++) {
        $item = $object[$index]
        $element = $chain[$index]

        if ($item.State -eq 'Absent') {
            continue
        }

        if ($item.State -eq 'Unknown') {
            $unmeasured.Add("${Path}: $element could not be measured ($($item.Reason))")
            continue
        }

        if ($item.IsReparsePoint) {
            $violation.Add("${Path}: $element is a reparse point, so the path does not name the object it protects")
        }

        if ($index -eq 0) {
            $role = if ($item.IsDirectory) { 'directory' } else { 'file' }
            $name = @('WriteData', 'AppendData')
            if ($item.IsDirectory) {
                $name += 'DeleteChild'
            }

            $name += @('Delete', 'WriteDac', 'WriteOwner')
        } else {
            $role = if ($index -eq 1) { 'parent directory' } else { 'ancestor directory' }
            $name = @('DeleteChild', 'Delete', 'WriteDac', 'WriteOwner')

            # The nearest directory that exists is where a missing file or directory would be created.
            if ($index -eq $firstExisting) {
                $name += $(if ($index -eq 1) { 'WriteData' } else { 'AppendData' })
            }
        }

        foreach ($rightName in $name) {
            $state = $item.Right[$rightName]
            $label = $script:RightLabel[$rightName][[int]$item.IsDirectory]

            if ($state -eq 'Granted') {
                $violation.Add("${Path}: this identity holds $label on the $role $element")
            } elseif ($state -ne 'Denied') {
                $unmeasured.Add("${Path}: $label on the $role $element could not be measured")
            }
        }
    }

    foreach ($root in @($WritableRoot | Where-Object -FilterScript { -not [string]::IsNullOrWhiteSpace($_) })) {
        if (Test-PathOverlap -Path $Path -WritableRoot $root) {
            $violation.Add("${Path}: overlaps the writable root $root")
        }
    }

    return [pscustomobject]@{
        Path = $Path
        Closed = ($violation.Count -eq 0 -and $unmeasured.Count -eq 0)
        Absent = $leafAbsent
        Violation = $violation.ToArray()
        Unmeasured = $unmeasured.ToArray()
    }
}

function Test-ControlImmutability {
    <#
        The controller needs evidence that the profile and the controls it pins are closed to every run
        identity, so they are measured whether or not the profile lists them as immutable: the profile
        itself, the four pinned controls, the live artifacts the profile declares, and every path in
        immutableControlPaths. Each is judged together with its whole chain of directories
        (Test-PathProtection) and against the roots the run may write. A missing control is a breach.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$ProfilePath,

        [Parameter(Mandatory)]
        $ContainmentProfile,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$WritableRoot = @()
    )

    $property = @($ContainmentProfile.PSObject.Properties.Name)
    $candidate = [System.Collections.Generic.List[string]]::new()
    $candidate.Add($ProfilePath)

    foreach ($name in @($script:PinnedControl) + @($script:LiveControl)) {
        if ($name -notin $property) {
            continue
        }

        $entry = $ContainmentProfile.$name

        if ($entry -is [System.Management.Automation.PSCustomObject] -and 'path' -in @($entry.PSObject.Properties.Name)) {
            $candidate.Add([string]$entry.path)
        }
    }

    if ('immutableControlPaths' -in $property) {
        foreach ($path in @($ContainmentProfile.immutableControlPaths)) {
            $candidate.Add([string]$path)
        }
    }

    $comparer = if ($script:OnWindows) { [System.StringComparer]::OrdinalIgnoreCase } else { [System.StringComparer]::Ordinal }
    $seen = [System.Collections.Generic.HashSet[string]]::new($comparer)
    $breach = [System.Collections.Generic.List[string]]::new()
    $unmeasured = [System.Collections.Generic.List[string]]::new()
    $perPathLimit = 6

    foreach ($path in $candidate) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            continue
        }

        try {
            $key = [System.IO.Path]::GetFullPath($path)
        } catch {
            $key = $path
        }

        if (-not $seen.Add($key)) {
            continue
        }

        try {
            $protection = Test-PathProtection -Path $path -WritableRoot $WritableRoot
        } catch {
            $unmeasured.Add("${path}: $($_.Exception.Message)")
            continue
        }

        if ($protection.Absent) {
            $breach.Add("$path (does not exist)")
        }

        foreach ($line in @($protection.Violation | Select-Object -First $perPathLimit)) {
            $breach.Add($line)
        }

        if (@($protection.Violation).Count -gt $perPathLimit) {
            $breach.Add("${path}: and $(@($protection.Violation).Count - $perPathLimit) more breaches")
        }

        foreach ($line in @($protection.Unmeasured)) {
            $unmeasured.Add($line)
        }
    }

    if ($breach.Count -gt 0) {
        $evidence = 'this identity can replace or loosen: ' + ($breach -join '; ')
        if ($unmeasured.Count -gt 0) {
            $evidence += '; not measurable: ' + ($unmeasured -join '; ')
        }

        return New-CheckResult -Name 'ControlImmutability' -Status 'Fail' -Evidence $evidence
    }

    if ($unmeasured.Count -gt 0) {
        return New-CheckResult -Name 'ControlImmutability' -Status 'Unavailable' -Evidence ('not measurable: ' + ($unmeasured -join '; '))
    }

    return New-CheckResult -Name 'ControlImmutability' -Status 'Pass' -Evidence 'the profile, every pinned control, every declared immutable path, and the directories above them are closed to this identity; its token is not read, so a disabled privilege or a filtered administrator group is not measured and the run identity must be a standard account'
}

function Get-IdentitySid {
    <#
        An account name, or a security identifier written as text, resolved to its security identifier.
        Nothing when it does not resolve: a name that cannot be resolved proves nothing about who a
        probe measured.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Identity
    )

    if ([string]::IsNullOrWhiteSpace($Identity)) {
        return $null
    }

    try {
        if ($Identity -cmatch '^S-1-\d+(?:-\d+)+$') {
            return ([System.Security.Principal.SecurityIdentifier]::new($Identity)).Value
        }

        return ([System.Security.Principal.NTAccount]::new($Identity).Translate([System.Security.Principal.SecurityIdentifier])).Value
    } catch {
        return $null
    }
}

function Get-CallerIdentity {
    <#
        The account this process runs as, read from its own token. It never comes from the profile or
        from an argument, so no input can make a probe claim to be someone else.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    try {
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()

        return [pscustomobject]@{ Name = $identity.Name; Sid = $identity.User.Value }
    } catch {
        return $null
    }
}

function Test-IdentityBinding {
    <#
        Every probe in this script measures the account that runs it. The profile declares which
        account is the controller and which is the worker, and -Role names the one being measured,
        so a result means something only when the verifier runs as that account: run as any other
        account, a Worker measurement would describe the wrong identity and read Pass. The two roles
        must also be two accounts, or "separate identities" is a claim and not a measurement.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Controller', 'Worker')]
        [string]$Role,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$ControllerIdentity,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$WorkerIdentity
    )

    if (-not $script:OnWindows) {
        return New-CheckResult -Name 'IdentityBinding' -Status 'Unavailable' -Evidence 'identity binding is implemented for Windows only'
    }

    $caller = Get-CallerIdentity

    if ($null -eq $caller) {
        return New-CheckResult -Name 'IdentityBinding' -Status 'Unavailable' -Evidence 'could not read the identity this verifier runs as'
    }

    $controllerSid = Get-IdentitySid -Identity $ControllerIdentity
    $workerSid = Get-IdentitySid -Identity $WorkerIdentity
    $unresolved = [System.Collections.Generic.List[string]]::new()

    if (-not $controllerSid) {
        $unresolved.Add("controller identity '$ControllerIdentity'")
    }

    if (-not $workerSid) {
        $unresolved.Add("worker identity '$WorkerIdentity'")
    }

    if ($unresolved.Count -gt 0) {
        return New-CheckResult -Name 'IdentityBinding' -Status 'Unavailable' -Evidence ('could not resolve ' + ($unresolved -join ' and '))
    }

    if ($controllerSid -ceq $workerSid) {
        return New-CheckResult -Name 'IdentityBinding' -Status 'Fail' -Evidence "the controller and the worker declare the same identity ($controllerSid)"
    }

    $declared = if ($Role -eq 'Controller') { $controllerSid } else { $workerSid }
    $other = if ($Role -eq 'Controller') { $workerSid } else { $controllerSid }

    if ($caller.Sid -cne $declared) {
        return New-CheckResult -Name 'IdentityBinding' -Status 'Fail' -Evidence "this verifier runs as $($caller.Name) ($($caller.Sid)), but the profile declares the $Role as $declared; a probe run as another account measures that account, not the $Role"
    }

    return New-CheckResult -Name 'IdentityBinding' -Status 'Pass' -Evidence "this verifier runs as $($caller.Name) ($($caller.Sid)), the identity the profile declares for the $Role; the other role is $other; its token is not read, so the account must be a standard one"
}

function Get-BytesDigest {
    <#
        The SHA-256 of exactly the bytes given, as lowercase hex. A file is hashed and parsed from
        one read of its bytes, so what was verified is what is used.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [byte[]]$Bytes
    )

    return [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}

function ConvertFrom-JsonByteArray {
    <#
        JSON from bytes that were already hashed. Invalid UTF-8 is refused instead of being replaced
        with substitute characters, and a byte-order mark is dropped.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [byte[]]$Bytes
    )

    $text = [System.Text.UTF8Encoding]::new($false, $true).GetString($Bytes)

    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) {
        $text = $text.Substring(1)
    }

    return ($text | ConvertFrom-Json -ErrorAction Stop)
}

function Get-JsonNode {
    <#
        Every property and every string of a parsed JSON document, at any depth, each with the path
        that leads to it. The walk keeps its own stack, so a deeply nested document is neither cut
        short by a serialization depth limit nor able to exhaust the call stack.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        $Document
    )

    $pending = [System.Collections.Generic.Stack[object[]]]::new()
    $pending.Push(@('', $Document))

    while ($pending.Count -gt 0) {
        $item = $pending.Pop()
        $path = [string]$item[0]
        $node = $item[1]

        if ($node -is [string]) {
            [pscustomobject]@{ Kind = 'String'; Path = $path; Name = $null; Value = $node }
        } elseif ($node -is [System.Management.Automation.PSCustomObject]) {
            foreach ($property in $node.PSObject.Properties) {
                $child = if ($path.Length -eq 0) { $property.Name } else { "$path.$($property.Name)" }

                [pscustomobject]@{ Kind = 'Property'; Path = $child; Name = $property.Name; Value = $property.Value }
                $pending.Push(@($child, $property.Value))
            }
        } elseif ($node -is [System.Collections.IEnumerable]) {
            $index = 0

            foreach ($element in $node) {
                $pending.Push(@("$path[$index]", $element))
                $index++
            }
        }
    }
}

function Format-LimitedList {
    <#
        The first few items of a list on one line with a count of the rest, so evidence stays short.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Item,

        [Parameter()]
        [ValidateRange(1, 100)]
        [int]$Limit = 3
    )

    $shown = @($Item | Select-Object -First $Limit) -join ', '

    if ($Item.Count -gt $Limit) {
        return "$shown and $($Item.Count - $Limit) more"
    }

    return $shown
}

function Format-RelayedText {
    <#
        Text that came from outside this script, in a form that is safe to put into evidence a model
        reads. Only printable ASCII is relayed. Every other character becomes one question mark, so a
        line a hostile source wrote cannot add lines, hide behind an escape sequence, or carry an
        instruction in characters a person cannot see: control and format characters, the Unicode tag
        block, variation selectors, fillers, blanks and spaces of other widths are all outside it. The
        length is capped, so the text cannot fill the report.

        The first version of this function replaced characters by category, and a deny-list is always
        one class short: the next review found variation selectors, Hangul fillers and the Braille blank
        passing it. A person can read printable ASCII, so that is what is let through. A letter with an
        accent in a path becomes a question mark, which costs a little readability and nothing else.

        The text is read by rune, not by UTF-16 unit, so a character outside the basic plane is one
        question mark and the cap never cuts a pair of units in half.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Text,

        [Parameter()]
        [ValidateRange(1, 1000)]
        [int]$Limit = 200
    )

    if ([string]::IsNullOrEmpty($Text)) {
        return ''
    }

    $clean = [System.Text.StringBuilder]::new()
    $cut = $false

    foreach ($rune in $Text.EnumerateRunes()) {
        if ($clean.Length -ge $Limit) {
            $cut = $true
            break
        }

        $null = $clean.Append($(if ($rune.Value -ge 0x20 -and $rune.Value -le 0x7E) { [char]$rune.Value } else { '?' }))
    }

    if ($cut) {
        $null = $clean.Append('...')
    }

    return $clean.ToString()
}

function Get-PathProblem {
    <#
        Why a path in the profile does not name one object. A relative path names whatever the
        working directory makes it, a dot segment hides where it leads, and a Windows short name is
        another spelling of a file whose real name the text does not show. On Windows a device or
        extended-length prefix is not normalized, so it is another spelling of the file it names, and
        a colon after the drive names a stream of a file instead of the file: a file reads the same
        under either spelling, and a comparison of the text sees two paths.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Path
    )

    $problem = [System.Collections.Generic.List[string]]::new()

    if ([string]::IsNullOrWhiteSpace($Path) -or -not [System.IO.Path]::IsPathFullyQualified($Path)) {
        $problem.Add('is not an absolute path')

        return $problem.ToArray()
    }

    if ($Path -match '(^|[\\/])\.{1,2}($|[\\/])') {
        $problem.Add('contains a dot segment')
    }

    if ($script:OnWindows -and $Path -match '~\d') {
        $problem.Add('contains a Windows short name')
    }

    if ($script:OnWindows -and $Path -match '^[\\/]{2}[?.][\\/]') {
        $problem.Add('is a device or extended-length path')
    }

    if ($script:OnWindows -and ($Path -replace '^[A-Za-z]:', '').Contains(':')) {
        $problem.Add('names an alternate data stream')
    }

    return $problem.ToArray()
}

function Test-VerifierBinding {
    <#
        The profile pins a verifier by path and digest, and ControlDigest hashes the file at that
        path. That proves nothing about the script that is running unless the two are the same file:
        a copy of the verifier that was edited to pass could run beside a pinned original. This check
        requires the running script to be the pinned path and to hash to the pinned digest.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        $ContainmentProfile,

        [Parameter(Mandatory)]
        [string]$ScriptPath
    )

    if ('verifier' -notin @($ContainmentProfile.PSObject.Properties.Name)) {
        return New-CheckResult -Name 'VerifierBinding' -Status 'Unavailable' -Evidence 'the profile pins no verifier'
    }

    $entry = $ContainmentProfile.verifier
    $comparison = if ($script:OnWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }

    try {
        $declared = [System.IO.Path]::GetFullPath([string]$entry.path)
        $running = [System.IO.Path]::GetFullPath($ScriptPath)
        $runningDigest = Get-BytesDigest -Bytes ([System.IO.File]::ReadAllBytes($running))
    } catch {
        return New-CheckResult -Name 'VerifierBinding' -Status 'Unavailable' -Evidence "could not read the running verifier: $($_.Exception.Message)"
    }

    if (-not $declared.Equals($running, $comparison)) {
        return New-CheckResult -Name 'VerifierBinding' -Status 'Fail' -Evidence "the profile pins the verifier at $declared, but the verifier that runs is $running"
    }

    if ($runningDigest -cne [string]$entry.sha256) {
        return New-CheckResult -Name 'VerifierBinding' -Status 'Fail' -Evidence "the verifier that runs hashes to $runningDigest, but the profile pins $($entry.sha256)"
    }

    return New-CheckResult -Name 'VerifierBinding' -Status 'Pass' -Evidence "the verifier that runs is the pinned file at $running with digest $runningDigest"
}

function Get-Verdict {
    <#
        Unavailable is not a lesser failure. A control that could not be measured was not verified,
        and the run must stop for it exactly as for a measured breach. A run in which no check ran
        verified nothing.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [hashtable[]]$Check
    )

    $blocking = @($Check | Where-Object -FilterScript { $_.status -ne 'Pass' })

    return [pscustomobject]@{
        Verdict = $(if (@($Check).Count -gt 0 -and $blocking.Count -eq 0) { 'Pass' } else { 'Fail' })
        Blocking = $blocking
    }
}

function Get-NotRunCheck {
    <#
        A check that was not run is Unavailable with the reason, never absent from the report and
        never a pass: the report always names every check the controller depends on.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [string[]]$Name,

        [Parameter(Mandatory)]
        [string]$Reason
    )

    return @($Name | ForEach-Object -Process { New-CheckResult -Name $_ -Status 'Unavailable' -Evidence "not run: $Reason" })
}

function Test-ReportPath {
    <#
        Where the verifier may write its report. It writes only a new or existing regular file in a
        directory that already exists, never over a protected control or inside one, never through a
        link, and it creates no directory: a report path is operator input and must not become a way
        to overwrite the evidence the report is about. Returns the reason for a refusal, nothing when
        the path is acceptable.

        The path is judged by the spelling rules of a profile path first, so a stream of a protected
        file, a device or extended-length spelling of it, a dot segment and a short name are refused
        rather than compared as text. On Windows a directory above the report that is a junction or a
        symbolic link is refused as well, because the path then reaches a file that its text does not
        name; on a POSIX system a link in the middle of a path is ordinary and only the last element
        is checked.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$ReportPath,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$ProtectedPath
    )

    if (-not [System.IO.Path]::IsPathFullyQualified($ReportPath)) {
        return 'the report path must be an absolute path'
    }

    $spelling = @(Get-PathProblem -Path $ReportPath)

    if ($spelling.Count -gt 0) {
        return "the report path $($spelling -join ' and ')"
    }

    $full = [System.IO.Path]::GetFullPath($ReportPath)
    $directory = [System.IO.Path]::GetDirectoryName($full)

    if ([string]::IsNullOrEmpty($directory) -or -not [System.IO.Directory]::Exists($directory)) {
        return "the directory of the report path does not exist (the verifier creates none): $directory"
    }

    if ([System.IO.Directory]::Exists($full)) {
        return "the report path names a directory: $full"
    }

    if ($script:OnWindows) {
        foreach ($ancestor in @(Get-PathChain -Path $directory)) {
            if ([System.IO.Directory]::Exists($ancestor) -and ([System.IO.File]::GetAttributes($ancestor) -band [System.IO.FileAttributes]::ReparsePoint)) {
                return "the directory of the report path goes through a link, so the path does not name the file it seems to: $ancestor"
            }
        }
    }

    foreach ($protected in @($ProtectedPath | Where-Object -FilterScript { -not [string]::IsNullOrWhiteSpace($_) })) {
        if (Test-PathOverlap -Path $full -WritableRoot $protected) {
            return "the report path is, or lies inside, a protected control: $protected"
        }
    }

    if ([System.IO.File]::Exists($full) -and ([System.IO.File]::GetAttributes($full) -band [System.IO.FileAttributes]::ReparsePoint)) {
        return "the report path is a link: $full"
    }

    return $null
}

function Test-ProfileSchema {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        $ContainmentProfile
    )

    $problem = [System.Collections.Generic.List[string]]::new()
    $propertyName = @($ContainmentProfile.PSObject.Properties.Name)
    $present = [System.Collections.Generic.HashSet[string]]::new([string[]]$propertyName, [System.StringComparer]::Ordinal)

    foreach ($name in $propertyName) {
        if (-not $script:AllowedKeySet.Contains($name)) {
            $problem.Add("unknown field '$name'")
        }
    }

    $required = @(
        'schemaVersion', 'verifier', 'hooksConfig', 'hookScript', 'ledgerAppender'
        'ledgerSink', 'chainHead', 'controllerEgressAllow', 'workerEgressAllow'
        'controllerIdentity', 'workerIdentity', 'immutableControlPaths', 'writableRoots'
    )

    foreach ($name in $required) {
        if (-not $present.Contains($name)) {
            $problem.Add("missing required field '$name'")
        }
    }

    if ($present.Contains('schemaVersion')) {
        # A loose comparison with 1 also accepts "1", $true, 1.0 and [1], none of which is the
        # integer the schema names.
        $version = $ContainmentProfile.schemaVersion

        if (($version -isnot [int] -and $version -isnot [long]) -or [long]$version -ne 1) {
            $problem.Add("'schemaVersion' must be the integer 1")
        }
    }

    foreach ($name in @('controllerIdentity', 'workerIdentity')) {
        if ($present.Contains($name) -and [string]::IsNullOrWhiteSpace([string]$ContainmentProfile.$name)) {
            $problem.Add("'$name' must name an identity")
        }
    }

    foreach ($name in @('controllerEgressAllow', 'workerEgressAllow')) {
        if ($present.Contains($name)) {
            $value = @($ContainmentProfile.$name)
            if ($value.Count -gt 0) {
                $problem.Add("'$name' must be empty; the controller and workers never reach a network")
            }
        }
    }

    foreach ($name in @($script:PinnedControl) + @($script:LiveControl)) {
        if (-not $present.Contains($name)) {
            continue
        }

        $entry = $ContainmentProfile.$name

        if ($entry -isnot [System.Management.Automation.PSCustomObject]) {
            $problem.Add("'$name' must be an object that declares a path and a sha256")
            continue
        }

        $entryKey = [System.Collections.Generic.HashSet[string]]::new([string[]]@($entry.PSObject.Properties.Name), [System.StringComparer]::Ordinal)

        if (-not $entryKey.Contains('path') -or -not $entryKey.Contains('sha256')) {
            $problem.Add("'$name' must declare a path and a sha256")
            continue
        }

        if ([string]$entry.sha256 -cnotmatch '^[0-9a-f]{64}$') {
            $problem.Add("'$name' declares a digest that is not lowercase 64-hex")
        }

        if ([string]$entry.path -match '[*?]') {
            $problem.Add("'$name' path contains a wildcard")
        }

        foreach ($pathProblem in @(Get-PathProblem -Path ([string]$entry.path))) {
            $problem.Add("'$name' path $pathProblem")
        }
    }

    foreach ($name in @('ledgerSink', 'chainHead')) {
        if (-not $present.Contains($name)) {
            continue
        }

        foreach ($pathProblem in @(Get-PathProblem -Path ([string]$ContainmentProfile.$name))) {
            $problem.Add("'$name' $pathProblem")
        }
    }

    foreach ($name in @('immutableControlPaths', 'writableRoots')) {
        if (-not $present.Contains($name)) {
            continue
        }

        foreach ($value in @($ContainmentProfile.$name)) {
            if ([string]$value -match '[*?]') {
                $problem.Add("'$name' contains a wildcard entry")
            }

            foreach ($pathProblem in @(Get-PathProblem -Path ([string]$value))) {
                $problem.Add("'$name' entry '$value' $pathProblem")
            }
        }
    }

    return $problem.ToArray()
}

function Get-HookRootBinding {
    <#
        The plugin root the hook command must find its script under, derived from the pinned script
        path. The shipped command looks for <PLUGIN_ROOT>/com.github.copilot/hooks/scripts/
        Block-RemoteMutation.ps1 before any other place, so a script pinned at that layout can be
        made the only one the command runs. Any other layout cannot be bound, and no root is guessed
        for it.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath
    )

    $layout = @('com.github.copilot', 'hooks', 'scripts', 'Block-RemoteMutation.ps1')
    $expected = '<root>/' + ($layout -join '/')

    if (-not [System.IO.Path]::IsPathFullyQualified($ScriptPath)) {
        return [pscustomobject]@{ Root = $null; Problem = "the pinned hook script path '$ScriptPath' is not an absolute path, so no plugin root can be derived from it" }
    }

    $comparison = if ($script:OnWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    $current = [System.IO.Path]::GetFullPath($ScriptPath)

    for ($index = $layout.Count - 1; $index -ge 0; $index--) {
        $leaf = [System.IO.Path]::GetFileName($current)

        if (-not $leaf.Equals($layout[$index], $comparison)) {
            return [pscustomobject]@{ Root = $null; Problem = "the pinned hook script is not at $expected, the layout the hook command resolves it from: found '$leaf' where '$($layout[$index])' is required in $ScriptPath" }
        }

        $current = [System.IO.Path]::GetDirectoryName($current)

        if ([string]::IsNullOrEmpty($current)) {
            return [pscustomobject]@{ Root = $null; Problem = "the pinned hook script is not at $expected, the layout the hook command resolves it from: $ScriptPath has no root above that layout" }
        }
    }

    return [pscustomobject]@{ Root = $current; Problem = $null }
}

function Get-GateFailure {
    <#
        The required checks that did not pass. A check that is absent from the list counts as one
        that did not pass: a control that was never measured is not a satisfied precondition.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [hashtable[]]$Check,

        [Parameter(Mandatory)]
        [string[]]$Require
    )

    $unmet = foreach ($name in $Require) {
        $found = @($Check | Where-Object -FilterScript { $_.name -ceq $name })

        if ($found.Count -eq 0 -or $found[0].status -cne 'Pass') {
            $name
        }
    }

    return [string[]]@($unmet)
}

function Get-HookInterpreter {
    <#
        The program a hook command line starts, as an absolute path. The line is run by a shell, and
        a host runs it from a working directory it does not choose: a shell looks a bare name up in
        that directory and then in PATH, and a relative path leads wherever that directory does, so
        only a command that names its program by absolute path can be shown to run the program that
        was measured. Any other first word is refused with the reason, and no path is guessed for it.
        A word the shell expands is refused as well, because the program it names is then not the
        text that was read.

        Only the first word names the program, but the rest of the line is read by the same shell, so
        it is read here the way a shell reads it and refused where that could start a program nobody
        measured. Refused anywhere: a line break; a character outside printable ASCII, because
        PowerShell reads curly quotes as quotes and some other characters as spaces or dashes, which
        this scan cannot follow; '%' and '!', which a shell expands before it reads the line, even
        inside quotes; and '$' and a backtick, which a PowerShell wrapper acts on inside double quotes
        ($(...) runs code). Refused outside double quotes: '&', '|', '<', '>', '^', '(' and ')', and a
        single quote, after which a double quote is text to PowerShell, so a scan that toggles on the
        double quote would think a semicolon is quoted that PowerShell reads as a separator. After the
        first unquoted ';' only the statement the shipped command ends with is accepted, for the
        PowerShell that a host wraps the line in. The program path may not hold a dot segment, which
        a shell follows through a link where a textual normalization does not.

        The program must be PowerShell, a program named powershell or pwsh. What PowerShell loads
        before its command is known and read here: it must be given -NoProfile, because the profile
        of the identity under test would otherwise run first and can change what the guard does, and
        the options before its script or command are read by Get-PowerShellLaunchOption, which allows
        only those that cannot change what runs first. What any other program loads cannot be read, so
        any other program is refused: cmd.exe, for one, runs the AutoRun commands of the registry of
        the identity that starts it unless it is given /d.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$CommandLine
    )

    $text = $CommandLine.TrimStart()
    $word = $null
    $rest = ''
    $quoted = $text.StartsWith('"')

    if ($text -match '[\r\n]') {
        return [pscustomobject]@{ Path = $null; Problem = 'the command spans more than one line, and a shell runs each line as a command of its own' }
    }

    # Read on the text as given, not as trimmed: TrimStart removes spaces that no shell reads as one.
    if ($CommandLine -cmatch '[^\x20-\x7E\t\r\n]') {
        return [pscustomobject]@{ Path = $null; Problem = 'the command line holds a character outside printable ASCII, and a shell may read some of those as a quote, a dash or a space that this scan does not (PowerShell reads curly quotes as quotes), so the line cannot be shown to run only what it appears to' }
    }

    if ($text -match '[%!$`]') {
        return [pscustomobject]@{ Path = $null; Problem = 'the command line holds a ''%'', a ''!'', a ''$'' or a backtick, which a shell expands or acts on even inside double quotes (a PowerShell wrapper runs $(...) there), so the program that runs is not only the one the text names' }
    }

    if ($quoted) {
        $close = $text.IndexOf('"', 1)

        if ($close -lt 0) {
            return [pscustomobject]@{ Path = $null; Problem = 'the command starts with a quote that is never closed' }
        }

        $word = $text.Substring(1, $close - 1)
        $rest = $text.Substring($close + 1)
    } else {
        $end = $text.IndexOfAny([char[]]@(' ', "`t"))
        $word = if ($end -lt 0) { $text } else { $text.Substring(0, $end) }
        $rest = if ($end -lt 0) { '' } else { $text.Substring($end) }
    }

    if ([string]::IsNullOrWhiteSpace($word)) {
        return [pscustomobject]@{ Path = $null; Problem = 'the command names no program' }
    }

    if ($word -match '[%^!]') {
        return [pscustomobject]@{ Path = $null; Problem = "the program '$word' contains a character the shell expands, so it is not the program the text names" }
    }

    if (-not $quoted -and $word -match "[&|<>']") {
        return [pscustomobject]@{ Path = $null; Problem = "the program word '$word' holds an unquoted shell character or single quote, which a shell reads as the start of another command, a redirection or a string" }
    }

    if ($word.StartsWith('\\') -or $word.StartsWith('//')) {
        return [pscustomobject]@{ Path = $null; Problem = "the program '$word' is named through a network or device path" }
    }

    if (-not [System.IO.Path]::IsPathFullyQualified($word)) {
        if ($word -match '[\\/:]') {
            return [pscustomobject]@{ Path = $null; Problem = "the program '$word' is a relative path, which leads wherever the working directory of the host is" }
        }

        return [pscustomobject]@{ Path = $null; Problem = "the program '$word' is a bare name, which the host looks up in its working directory and then in PATH" }
    }

    if ($word -match '(^|[\\/])\.{1,2}($|[\\/])') {
        return [pscustomobject]@{ Path = $null; Problem = "the program '$word' contains a dot segment, which hides where it leads: a shell follows '..' through a link where this check normalizes the text" }
    }

    $inQuote = $false
    $head = $rest

    for ($position = 0; $position -lt $rest.Length; $position++) {
        $character = $rest[$position]

        if ($character -eq [char]34) {
            $inQuote = -not $inQuote
        } elseif (-not $inQuote -and $character -eq [char]59) {
            # The shipped Windows command ends with one statement after a semicolon, for the PowerShell
            # a host wraps it in. Any other text after a semicolon would run a second program.
            $tail = $rest.Substring($position + 1).Trim()

            if (-not [string]::Equals($tail, $script:HookExitTail, [System.StringComparison]::Ordinal)) {
                return [pscustomobject]@{ Path = $null; Problem = 'the command line has an unquoted semicolon followed by text other than the one statement the shipped command ends with, which a host that wraps the line in PowerShell would run as a second command' }
            }

            $head = $rest.Substring(0, $position)
            break
        } elseif (-not $inQuote -and $character -eq [char]39) {
            return [pscustomobject]@{ Path = $null; Problem = 'the command line has a single quote outside double quotes, which a PowerShell wrapper reads as the start of a string in which a double quote is text, so that shell and this scan can disagree about where a quoted part ends and a semicolon begins' }
        } elseif (-not $inQuote -and '&|<>^()'.IndexOf($character) -ge 0) {
            return [pscustomobject]@{ Path = $null; Problem = "the command line has an unquoted '$character' after its program, which a shell reads as another command, a redirection, an escape or a group, so the program that runs is not only the one named" }
        }
    }

    $program = [System.IO.Path]::GetFullPath($word)
    $name = [System.IO.Path]::GetFileName($program)

    if ($name -inotmatch '\A(pwsh|powershell)(\.exe)?\z') {
        return [pscustomobject]@{ Path = $null; Problem = "the program '$name' is not PowerShell (a program named powershell or pwsh): this check reads what PowerShell loads before its command and cannot read what any other program loads, so a command that starts anything else is not shown to run the guard and nothing else" }
    }

    $token = @([regex]::Matches($head, '"[^"]*"|\S+') | ForEach-Object { $_.Value.Trim('"') })
    $scan = Get-PowerShellLaunchOption -Argument $token

    if ($null -ne $scan.Problem) {
        return [pscustomobject]@{ Path = $null; Problem = "the PowerShell command line cannot be trusted: $($scan.Problem)" }
    }

    if (-not $scan.NoProfile) {
        return [pscustomobject]@{ Path = $null; Problem = 'the interpreter is PowerShell and the command does not pass -NoProfile before its script or command, so the profile of the identity that runs it is loaded first and can change what the guard does' }
    }

    return [pscustomobject]@{ Path = $program; Problem = $null }
}

function Invoke-HookPayload {
    <#
        The hook command is a full command line, so it runs through a throwaway
        shell script rather than being split into an executable and arguments;
        re-quoting it here is exactly how a probe stops matching the command the
        agent loop actually executes.

        The shell is the system one, not whatever ComSpec names, and it is started with /d: cmd.exe
        runs the AutoRun commands of the registry of the identity that starts it unless it is given
        /d, and they would run before the probe does and could answer for the guard. The command sees
        the environment it is given: a probe that inherits the caller's variables measures the caller's
        choices. The command starts in a folder of its own that holds nothing but the script, and the
        shell is told not to look for a command in the working directory, so a program a repository
        planted in
        the directory the verifier was started from is never the one that runs. That instruction is
        applied after the caller's variables and cannot be removed by them.
        A command that does not finish is stopped and refused, never waited for.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [string]$CommandLine,

        [Parameter(Mandatory)]
        [string]$Payload,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.IDictionary]$EnvironmentVariable,

        [Parameter()]
        [ValidateRange(1, 600)]
        [int]$TimeoutSecond = 30
    )

    $workRoot = Join-Path ([System.IO.Path]::GetTempPath()) "containment-hook-$([guid]::NewGuid().ToString('N'))"
    $null = New-Item -Path $workRoot -ItemType Directory -Force
    $process = $null

    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()

        if ($script:OnWindows) {
            $scriptPath = Join-Path $workRoot 'probe.cmd'
            [System.IO.File]::WriteAllText($scriptPath, "@echo off`r`n$CommandLine`r`n", [System.Text.ASCIIEncoding]::new())
            $startInfo.FileName = [System.IO.Path]::Combine([System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::System), 'cmd.exe')
            $startInfo.ArgumentList.Add('/d')
            $startInfo.ArgumentList.Add('/c')
            $startInfo.ArgumentList.Add($scriptPath)
        } else {
            $scriptPath = Join-Path $workRoot 'probe.sh'
            [System.IO.File]::WriteAllText($scriptPath, "#!/bin/sh`n$CommandLine`n", [System.Text.UTF8Encoding]::new($false))
            $startInfo.FileName = '/bin/sh'
            $startInfo.ArgumentList.Add($scriptPath)
        }

        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.WorkingDirectory = $workRoot
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.StandardInputEncoding = [System.Text.UTF8Encoding]::new($false)

        foreach ($name in $EnvironmentVariable.Keys) {
            if ($null -eq $EnvironmentVariable[$name]) {
                $null = $startInfo.Environment.Remove([string]$name)
            } else {
                $startInfo.Environment[[string]$name] = [string]$EnvironmentVariable[$name]
            }
        }

        if ($script:OnWindows) {
            $startInfo.Environment['NoDefaultCurrentDirectoryInExePath'] = '1'
        }

        $process = [System.Diagnostics.Process]::Start($startInfo)
        # Read both streams while the command runs: a full pipe would otherwise block it for good.
        $standardOutput = $process.StandardOutput.ReadToEndAsync()
        $standardError = $process.StandardError.ReadToEndAsync()

        try {
            $process.StandardInput.Write($Payload)
            $process.StandardInput.Close()
        } catch [System.IO.IOException] {
            Write-Verbose 'the command ended before it read its input'
        }

        if (-not $process.WaitForExit($TimeoutSecond * 1000)) {
            try {
                $process.Kill($true)
            } catch {
                Write-Verbose "could not stop the hook command: $($_.Exception.Message)"
            }

            throw "the hook command did not finish within $TimeoutSecond seconds"
        }

        $process.WaitForExit()
        $null = $standardOutput.Wait(5000)
        $null = $standardError.Wait(5000)

        return [int]$process.ExitCode
    } finally {
        if ($null -ne $process) {
            $process.Dispose()
        }

        Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-HookContract {
    <#
        Runs the pinned hook through the pinned hooks.json command and measures its real exit codes.

        The command line comes from a file and is executed, so this runs only on bytes it has itself
        hashed: hooks.json is read once, hashed, and parsed from those bytes, and the script is
        hashed here as well, so a file that changed after ControlDigest is refused, not executed.

        Which script runs is decided by the command, not by this check. PLUGIN_ROOT is therefore set
        to the root the pinned script lives under and every other place the command looks is given
        an empty directory. A decoy tree proves the command honours that: a decoy script under
        PLUGIN_ROOT must run ahead of a decoy in the user profile. A command that resolves its script
        any other way cannot be shown to run the pinned one, and fails.

        Which program runs the script is decided by the command as well, and a program found by a
        search is not one that was measured: a bare name is looked up in the working directory of
        the host and then in PATH. The command must therefore start with the absolute path of its
        interpreter, and that interpreter, with its folder and every folder above it, must be closed
        to this identity before anything is run. A command that does not, fails; an interpreter that
        cannot be measured is unmeasured, and the command is not run in either case.

        Which file the command comes from is decided by the host: it loads hooks.json from the
        plugin root the hook script lives under. The pinned hooks.json must therefore be that file,
        <root>/com.github.copilot/hooks/hooks.json for the root derived from the pinned script; a
        byte-identical file anywhere else is not the one a host reads, and fails before it is run.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$HookConfigPath,

        [Parameter(Mandatory)]
        [string]$HookConfigSha256,

        [Parameter(Mandatory)]
        [string]$HookScriptPath,

        [Parameter(Mandatory)]
        [string]$HookScriptSha256,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$WritableRoot = @()
    )

    $binding = Get-HookRootBinding -ScriptPath $HookScriptPath

    if ($null -ne $binding.Problem) {
        return New-CheckResult -Name 'HookContract' -Status 'Unavailable' -Evidence $binding.Problem
    }

    try {
        $configBytes = [System.IO.File]::ReadAllBytes($HookConfigPath)
        $scriptBytes = [System.IO.File]::ReadAllBytes($HookScriptPath)
    } catch {
        return New-CheckResult -Name 'HookContract' -Status 'Unavailable' -Evidence "could not read a pinned hook control: $($_.Exception.Message)"
    }

    $configDigest = Get-BytesDigest -Bytes $configBytes

    if ($configDigest -cne $HookConfigSha256) {
        return New-CheckResult -Name 'HookContract' -Status 'Fail' -Evidence "hooks.json hashes to $configDigest but the profile pins $HookConfigSha256; its command was not run"
    }

    $scriptDigest = Get-BytesDigest -Bytes $scriptBytes

    if ($scriptDigest -cne $HookScriptSha256) {
        return New-CheckResult -Name 'HookContract' -Status 'Fail' -Evidence "the hook script hashes to $scriptDigest but the profile pins $HookScriptSha256; hooks.json was not run"
    }

    # The command that is measured must be the one a host runs. A host loads hooks.json from the
    # plugin root the hook script lives under, so the pinned file has to be that one: a
    # byte-identical file anywhere else is not the file the host reads.
    $comparison = if ($script:OnWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    $ownConfig = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($binding.Root, 'com.github.copilot', 'hooks', 'hooks.json'))
    $pinnedConfig = [System.IO.Path]::GetFullPath($HookConfigPath)

    if (-not $pinnedConfig.Equals($ownConfig, $comparison)) {
        return New-CheckResult -Name 'HookContract' -Status 'Fail' -Evidence "the pinned hooks.json $pinnedConfig is not the plugin's own at $ownConfig, the file a host loads from the plugin root the hook script lives under, so the command that was measured is not shown to be the one a host runs. It was not run"
    }

    try {
        $configuration = ConvertFrom-JsonByteArray -Bytes $configBytes
    } catch {
        return New-CheckResult -Name 'HookContract' -Status 'Unavailable' -Evidence 'hooks.json is not valid JSON'
    }

    if ($configuration -isnot [System.Management.Automation.PSCustomObject]) {
        return New-CheckResult -Name 'HookContract' -Status 'Fail' -Evidence 'hooks.json is not a JSON object, so it registers no PreToolUse hook'
    }

    $preToolUse = @()
    $otherEvent = @()
    $hooksProperty = $configuration.PSObject.Properties['hooks']

    if ($null -ne $hooksProperty -and $hooksProperty.Value -is [System.Management.Automation.PSCustomObject]) {
        $eventProperty = $hooksProperty.Value.PSObject.Properties

        if ($null -ne $eventProperty['PreToolUse']) {
            $preToolUse = @($eventProperty['PreToolUse'].Value)
        }

        $otherEvent = @($eventProperty | Where-Object { -not [string]::Equals($_.Name, 'PreToolUse', [System.StringComparison]::Ordinal) -and @($_.Value).Count -gt 0 } | ForEach-Object { $_.Name })
    }

    if ($preToolUse.Count -ne 1) {
        return New-CheckResult -Name 'HookContract' -Status 'Fail' -Evidence "expected exactly one PreToolUse hook, measured $($preToolUse.Count)"
    }

    if ($otherEvent.Count -gt 0) {
        return New-CheckResult -Name 'HookContract' -Status 'Fail' -Evidence "hooks.json registers hooks besides the guard ($($otherEvent -join ', ')), whose scripts are neither pinned nor measured, so a contained deployment pins a hooks.json that registers only the guard. It was not run"
    }

    $entry = $preToolUse[0]

    if ($entry -isnot [System.Management.Automation.PSCustomObject]) {
        return New-CheckResult -Name 'HookContract' -Status 'Fail' -Evidence 'the PreToolUse hook is not an object. It was not run'
    }

    $typeProperty = $entry.PSObject.Properties['type']
    $hookType = if ($null -ne $typeProperty) { $typeProperty.Value } else { $null }

    if ($hookType -isnot [string] -or -not [string]::Equals($hookType, 'command', [System.StringComparison]::Ordinal)) {
        return New-CheckResult -Name 'HookContract' -Status 'Fail' -Evidence "the PreToolUse hook is of type '$(Format-RelayedText -Text ([string]$hookType))', not command, so the command line that was read is not what a host runs. It was not run"
    }

    if ($null -ne $entry.PSObject.Properties['matcher']) {
        return New-CheckResult -Name 'HookContract' -Status 'Fail' -Evidence 'the PreToolUse hook has a matcher, which narrows the tools it runs for, so the guard would not see every tool call. It was not run'
    }

    $timeoutProperty = $entry.PSObject.Properties['timeout']
    $timeoutSeconds = if ($null -ne $timeoutProperty) { $timeoutProperty.Value } else { $null }

    if (($timeoutSeconds -isnot [int] -and $timeoutSeconds -isnot [long]) -or [long]$timeoutSeconds -lt 1 -or [long]$timeoutSeconds -gt 600) {
        return New-CheckResult -Name 'HookContract' -Status 'Fail' -Evidence 'the PreToolUse hook declares no timeout of 1 to 600 seconds as an integer, so the time a host allows it is not known. It was not run'
    }

    # The entry is a closed set of keys. Any other key is one this check does not read, and a host may
    # act on it: its own name for the timeout, an environment, a working directory. The entry that was
    # measured would then not be the one that runs.
    $unread = @($entry.PSObject.Properties.Name | Where-Object { -not $script:EntryKeySet.Contains($_) })

    if ($unread.Count -gt 0) {
        $named = @($unread | Select-Object -First 6 | ForEach-Object { "'$(Format-RelayedText -Text $_ -Limit 40)'" }) -join ', '

        return New-CheckResult -Name 'HookContract' -Status 'Fail' -Evidence "the PreToolUse hook carries keys this check does not read ($named), and a host may act on them, so the entry that was measured is not shown to be the one that runs; only type, timeout and the command keys ($($script:CommandKey -join ', ')) are allowed. It was not run"
    }

    # A host reads one of several keys for the command, and which one is its choice, so every key
    # that holds a command must hold the same one: then the command that is probed is the one that runs.
    $commandText = [ordered]@{}

    foreach ($key in $script:CommandKey) {
        $keyProperty = $entry.PSObject.Properties[$key]

        if ($null -ne $keyProperty -and $keyProperty.Value -is [string] -and -not [string]::IsNullOrWhiteSpace($keyProperty.Value)) {
            $commandText[$key] = $keyProperty.Value
        }
    }

    $commandValue = @($commandText.Values)

    if (@($commandValue | Where-Object { -not [string]::Equals($_, $commandValue[0], [System.StringComparison]::Ordinal) }).Count -gt 0) {
        return New-CheckResult -Name 'HookContract' -Status 'Fail' -Evidence "the PreToolUse hook carries different commands under $($commandText.Keys -join ', '), and a host chooses which one it runs, so only one of them can be shown to be the one probed; pin the same command under every key. It was not run"
    }

    $commandLine = if ($script:OnWindows -and $commandText.Contains('windows')) {
        [string]$commandText['windows']
    } elseif ($commandText.Contains('command')) {
        [string]$commandText['command']
    } else {
        ''
    }

    if ([string]::IsNullOrWhiteSpace($commandLine)) {
        return New-CheckResult -Name 'HookContract' -Status 'Unavailable' -Evidence 'PreToolUse hook declares no command for this platform'
    }

    $interpreter = Get-HookInterpreter -CommandLine $commandLine

    if ($null -ne $interpreter.Problem) {
        return New-CheckResult -Name 'HookContract' -Status 'Fail' -Evidence "the hook command does not start with the absolute path of its interpreter ($($interpreter.Problem)), so the program that runs it cannot be shown to be one that was measured; pin a command that starts with an absolute interpreter path. It was not run"
    }

    try {
        $protection = Test-PathProtection -Path $interpreter.Path -WritableRoot $WritableRoot
    } catch {
        return New-CheckResult -Name 'HookContract' -Status 'Unavailable' -Evidence "the interpreter $($interpreter.Path) could not be measured, so the hook command was not run: $($_.Exception.Message)"
    }

    if ($protection.Absent) {
        return New-CheckResult -Name 'HookContract' -Status 'Fail' -Evidence "the interpreter $($interpreter.Path) does not exist, so the hook command was not run"
    }

    if (@($protection.Violation).Count -gt 0) {
        $detail = @($protection.Violation | Select-Object -First 6) -join '; '

        return New-CheckResult -Name 'HookContract' -Status 'Fail' -Evidence "the interpreter $($interpreter.Path) can be replaced by this identity, so what the probe reports proves nothing and the hook command was not run: $detail"
    }

    if (@($protection.Unmeasured).Count -gt 0) {
        $detail = @($protection.Unmeasured | Select-Object -First 6) -join '; '

        return New-CheckResult -Name 'HookContract' -Status 'Unavailable' -Evidence "the interpreter $($interpreter.Path) could not be shown to be closed to this identity, so the hook command was not run: $detail"
    }

    $resolvedScript = [System.IO.Path]::GetFullPath($HookScriptPath)
    $workRoot = Join-Path ([System.IO.Path]::GetTempPath()) "containment-hook-contract-$([guid]::NewGuid().ToString('N'))"

    try {
        $null = New-Item -Path $workRoot -ItemType Directory -Force
        $emptyHome = Join-Path $workRoot 'empty-home'
        $null = New-Item -Path $emptyHome -ItemType Directory -Force

        # Two decoy scripts: one where the command looks first, one in the user profile it falls
        # back to. Only a command that takes PLUGIN_ROOT ahead of the profile runs the first.
        $pluginDecoyRoot = Join-Path $workRoot 'decoy-plugin'
        $pluginDecoyDirectory = Join-Path $pluginDecoyRoot 'com.github.copilot/hooks/scripts'
        $profileDecoyHome = Join-Path $workRoot 'decoy-profile'
        $profileDecoyDirectory = Join-Path $profileDecoyHome '.copilot/hooks/scripts'

        foreach ($decoy in @(
                @{ Directory = $pluginDecoyDirectory; Name = 'plugin'; Code = 7 }
                @{ Directory = $profileDecoyDirectory; Name = 'profile'; Code = 8 }
            )) {
            $null = New-Item -Path $decoy.Directory -ItemType Directory -Force
            $body = "Set-Content -LiteralPath (Join-Path `$PSScriptRoot 'ran.txt') -Value '$($decoy.Name)'`nexit $($decoy.Code)`n"
            [System.IO.File]::WriteAllText((Join-Path $decoy.Directory 'Block-RemoteMutation.ps1'), $body, [System.Text.UTF8Encoding]::new($false))
        }

        $safePayload = '{"tool_name":"read_file","tool_input":{"filePath":"README.md"}}'
        $clock = [System.Diagnostics.Stopwatch]::new()

        try {
            $clock.Restart()
            $canaryExit = Invoke-HookPayload -CommandLine $commandLine -Payload $safePayload -EnvironmentVariable @{
                PLUGIN_ROOT = $pluginDecoyRoot
                USERPROFILE = $profileDecoyHome
                HOME = $profileDecoyHome
            }
        } catch {
            return New-CheckResult -Name 'HookContract' -Status 'Unavailable' -Evidence "could not run the resolution probe: $($_.Exception.Message)"
        }

        if ($clock.Elapsed.TotalSeconds -ge $timeoutSeconds) {
            return New-CheckResult -Name 'HookContract' -Status 'Fail' -Evidence "the hook command took $([int][Math]::Ceiling($clock.Elapsed.TotalSeconds)) seconds, which is not under the timeout of $timeoutSeconds seconds the PreToolUse hook declares, so a host would stop it before it could answer"
        }

        $pluginDecoyRan = Test-Path -LiteralPath (Join-Path $pluginDecoyDirectory 'ran.txt')
        $profileDecoyRan = Test-Path -LiteralPath (Join-Path $profileDecoyDirectory 'ran.txt')

        if ($canaryExit -ne 7 -or -not $pluginDecoyRan -or $profileDecoyRan) {
            return New-CheckResult -Name 'HookContract' -Status 'Fail' -Evidence "the hook command does not take its script from PLUGIN_ROOT ahead of the user profile (a decoy under PLUGIN_ROOT gave exit $canaryExit; the PLUGIN_ROOT decoy ran: $pluginDecoyRan; the user-profile decoy ran: $profileDecoyRan), so the pinned script cannot be shown to be the one it runs"
        }

        # Fixed synthetic payloads: one benign, one remote mutation, one issue
        # mutation. Nothing here is derived from the repository under test.
        $case = [ordered]@{
            safe = @{ expected = 0; payload = $safePayload }
            push = @{ expected = 2; payload = '{"tool_name":"run_in_terminal","tool_input":{"command":"git push origin main"}}' }
            issue = @{ expected = 2; payload = '{"tool_name":"run_in_terminal","tool_input":{"command":"gh issue close 12"}}' }
        }

        $measured = [System.Collections.Generic.List[string]]::new()
        $failed = $false

        foreach ($name in $case.Keys) {
            try {
                $clock.Restart()
                $exitCode = Invoke-HookPayload -CommandLine $commandLine -Payload $case[$name].payload -EnvironmentVariable @{
                    PLUGIN_ROOT = $binding.Root
                    USERPROFILE = $emptyHome
                    HOME = $emptyHome
                }
            } catch {
                return New-CheckResult -Name 'HookContract' -Status 'Unavailable' -Evidence "could not run the $name payload: $($_.Exception.Message)"
            }

            if ($clock.Elapsed.TotalSeconds -ge $timeoutSeconds) {
                return New-CheckResult -Name 'HookContract' -Status 'Fail' -Evidence "the hook command took $([int][Math]::Ceiling($clock.Elapsed.TotalSeconds)) seconds for the $name payload, which is not under the timeout of $timeoutSeconds seconds the PreToolUse hook declares, so a host would stop it before it could answer"
            }

            $measured.Add("$name=$exitCode")

            if ($exitCode -ne $case[$name].expected) {
                $failed = $true
            }
        }
    } finally {
        Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    $evidence = 'expected 0,2,2 and measured ' + ($measured -join ' ') + " from the pinned script $resolvedScript through the interpreter $($interpreter.Path)"

    if ($failed) {
        return New-CheckResult -Name 'HookContract' -Status 'Fail' -Evidence $evidence
    }

    return New-CheckResult -Name 'HookContract' -Status 'Pass' -Evidence $evidence
}

function Get-GrantRoot {
    <#
        Where the guard keeps the Remote grants of the identity that runs it. The expression is the
        guard's own, so this measures the folder the guard reads.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $profileRoot = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::LocalApplicationData)

    if ([string]::IsNullOrWhiteSpace($profileRoot)) {
        return $null
    }

    return [System.IO.Path]::Combine($profileRoot, 'CopilotAtelier', 'grants')
}

function Test-GrantRecorderUnregistered {
    <#
        A Remote grant lets one named remote mutation through the guard, and the UserPromptSubmit
        hook records it from a Grant marker in prompt text. In a contained run that text includes
        specification and issue content pasted into prompts, none of it the operator's own, so no
        hook that records grants may be registered there.

        What a Pass says, and no more. The pinned hooks.json is of a shape this check reads, an object
        whose hooks object holds only lists; it registers no hook on the prompt event and does not
        contain the name of the recorder; and the grants folder of the identity that runs holds
        nothing, so no grant recorded earlier is waiting. Both reads of the file cover every property
        and string at any depth, so a nested matcher group or a field the host reads under another
        name is covered: a prompt event is a property named for it that holds anything, and the
        recorder is named by any string or property name that contains it, whatever the casing. A
        shape that is not read is unmeasured, never a pass.

        What it does not say. It does not say that no grant can exist: the guard honors any
        well-formed grant file in a folder the run owns, so a run that writes one itself is not
        stopped here, and egress and credentials are the boundary against a remote mutation. It
        matches a name, not a behavior: a recorder under another name, a wildcard, or a name built
        by an expansion is not seen. It does not read a hook file the host finds outside the pinned
        file, such as a user-level or workspace hooks folder or an installed copy of the plugin.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [string]$HookConfigPath,

        [Parameter(Mandatory)]
        [string]$HookConfigSha256,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$GrantRoot
    )

    try {
        $configBytes = [System.IO.File]::ReadAllBytes($HookConfigPath)
    } catch {
        return New-CheckResult -Name 'GrantRecorderUnregistered' -Status 'Unavailable' -Evidence "could not read the pinned hooks.json: $($_.Exception.Message)"
    }

    $configDigest = Get-BytesDigest -Bytes $configBytes

    if ($configDigest -cne $HookConfigSha256) {
        return New-CheckResult -Name 'GrantRecorderUnregistered' -Status 'Fail' -Evidence "hooks.json hashes to $configDigest but the profile pins $HookConfigSha256; it was not read as the pinned file"
    }

    try {
        $configuration = ConvertFrom-JsonByteArray -Bytes $configBytes
    } catch {
        return New-CheckResult -Name 'GrantRecorderUnregistered' -Status 'Unavailable' -Evidence 'hooks.json is not valid JSON'
    }

    $finding = [System.Collections.Generic.List[string]]::new()
    $node = @(Get-JsonNode -Document $configuration)

    $promptPath = [string[]]@(
        $node |
            Where-Object { $_.Kind -eq 'Property' -and $_.Name -imatch '^userpromptsubmit(ted)?$' -and @($_.Value).Count -gt 0 } |
            ForEach-Object { $_.Path }
    )

    if ($promptPath.Count -gt 0) {
        [Array]::Sort($promptPath, [System.StringComparer]::Ordinal)
        $finding.Add("hooks.json registers a prompt hook at $(Format-LimitedList -Item $promptPath), which records a Remote grant from a Grant marker in any prompt text, including specification or issue text pasted into a prompt")
    }

    $recorderPath = [string[]]@(
        $node |
            Where-Object {
                ($_.Kind -eq 'String' -and $_.Value -imatch 'Add-RemoteGrant') -or
                ($_.Kind -eq 'Property' -and $_.Name -imatch 'Add-RemoteGrant')
            } |
            ForEach-Object { $_.Path } |
            Select-Object -Unique
    )

    if ($recorderPath.Count -gt 0) {
        [Array]::Sort($recorderPath, [System.StringComparer]::Ordinal)
        $finding.Add("hooks.json names the Remote grant recorder at $(Format-LimitedList -Item $recorderPath), so a command under any event can record a Remote grant")
    }

    $shapeProblem = $null

    if ($configuration -isnot [System.Management.Automation.PSCustomObject]) {
        $shapeProblem = 'the document is not a JSON object'
    } else {
        $hooksProperty = $configuration.PSObject.Properties['hooks']

        if ($null -eq $hooksProperty) {
            $shapeProblem = "it has no 'hooks' object"
        } elseif ($hooksProperty.Value -isnot [System.Management.Automation.PSCustomObject]) {
            $shapeProblem = "'hooks' is not an object"
        } else {
            $notList = @($hooksProperty.Value.PSObject.Properties | Where-Object { $_.Value -isnot [System.Array] } | ForEach-Object { $_.Name })

            if ($notList.Count -gt 0) {
                $shapeProblem = "the event $($notList -join ', ') does not hold a list"
            }
        }
    }

    $root = if ([string]::IsNullOrWhiteSpace($GrantRoot)) { Get-GrantRoot } else { $GrantRoot }
    $unmeasured = $null

    if ([string]::IsNullOrWhiteSpace($root)) {
        $unmeasured = 'the grants folder of this identity cannot be located'
    } else {
        try {
            if ([System.IO.Directory]::Exists($root)) {
                $waiting = @([System.IO.Directory]::EnumerateFileSystemEntries($root)).Count

                if ($waiting -gt 0) {
                    $finding.Add("$waiting entries wait in the grants folder $root, so a Remote grant recorded earlier can still authorize a remote mutation")
                }
            }
        } catch {
            $unmeasured = "could not list the grants folder ${root}: $($_.Exception.Message)"
        }
    }

    if ($finding.Count -gt 0) {
        return New-CheckResult -Name 'GrantRecorderUnregistered' -Status 'Fail' -Evidence ($finding -join '; ')
    }

    if ($null -ne $shapeProblem) {
        return New-CheckResult -Name 'GrantRecorderUnregistered' -Status 'Unavailable' -Evidence "hooks.json has a shape this check does not read ($shapeProblem), so a hook registered in it would not be seen"
    }

    if ($null -ne $unmeasured) {
        return New-CheckResult -Name 'GrantRecorderUnregistered' -Status 'Unavailable' -Evidence $unmeasured
    }

    return New-CheckResult -Name 'GrantRecorderUnregistered' -Status 'Pass' -Evidence "the pinned hooks.json registers no prompt hook and does not contain the name Add-RemoteGrant, and $root holds no Remote grant; a recorder under another name and a grant file a run writes itself are not measured"
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

    $moduleProblem = Get-FirewallModuleProblem

    if (-not [string]::IsNullOrEmpty($moduleProblem)) {
        return New-CheckResult -Name 'EgressPolicy' -Status 'Unavailable' -Evidence $moduleProblem
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
    <#
        Measures credential and proxy material in the environment and the credential helpers git
        would use. The git that answers is evidence only if this identity cannot have replaced it,
        so it is run only after it was shown to be closed to the run: a git the run can overwrite
        could report any answer. It is also an executable run as the identity that verifies, so it is
        run only when the controls that identity is trusted on have passed (GitGateReason names what
        has not, and is empty when nothing is missing); the variables are measured either way.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$WritableRoot = @(),

        [Parameter()]
        [AllowEmptyString()]
        [string]$GitGateReason = ''
    )

    # The git steering variables are measured next to the credential ones,
    # because each of them can hide a helper from the child or add one to it.
    # Their presence is the failure; their value is never printed, since a
    # value is exactly where a token would sit.
    $variable = @(
        'GH_TOKEN', 'GITHUB_TOKEN', 'HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'SSH_AUTH_SOCK'
        'GIT_ASKPASS', 'SSH_ASKPASS', 'GIT_SSH', 'GIT_SSH_COMMAND'
        'GIT_CONFIG_GLOBAL', 'GIT_CONFIG_SYSTEM', 'GIT_CONFIG_COUNT', 'GIT_CONFIG_PARAMETERS'
        'XDG_CONFIG_HOME'
    )
    $found = [System.Collections.Generic.List[string]]::new()

    foreach ($name in $variable) {
        if (-not [string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($name))) {
            $found.Add($name)
        }
    }

    $gitEvidence = ''
    $gitProblem = ''
    $gitBreach = ''
    $gitTrusted = $false
    $gitSkipped = -not [string]::IsNullOrWhiteSpace($GitGateReason)
    $gitPath = if ($gitSkipped) { '' } else { Resolve-GitExecutable }

    if (-not [string]::IsNullOrWhiteSpace($gitPath)) {
        try {
            $gitProtection = Test-PathProtection -Path $gitPath -WritableRoot $WritableRoot

            if (@($gitProtection.Violation).Count -gt 0) {
                $gitBreach = "git ($gitPath) can be replaced by this identity, so what it reports proves nothing and it was not run: " + (@($gitProtection.Violation | Select-Object -First 6) -join '; ')
            } elseif (@($gitProtection.Unmeasured).Count -gt 0) {
                $gitProblem = "git ($gitPath) could not be shown to be closed to this identity, so it was not run: " + (@($gitProtection.Unmeasured | Select-Object -First 6) -join '; ')
            } else {
                $gitTrusted = $true
            }
        } catch {
            $gitProblem = "git ($gitPath) could not be measured, so it was not run: $($_.Exception.Message)"
        }
    }

    if ($gitSkipped) {
        $gitProblem = "git was not run: it executes as this identity, which is trusted only after $GitGateReason, so its credential helpers were not read"
    } elseif ([string]::IsNullOrWhiteSpace($gitPath)) {
        # A git that cannot be resolved is an unmeasured check. "Not installed,
        # therefore clean" would let an empty PATH prove containment.
        $gitProblem = 'git could not be resolved to an absolute application path, so its credential helpers were not measured'
    } elseif ($gitTrusted) {
        # The sentinel makes an empty credential result mean something: a child
        # that crashed or printed nothing must not read as "no helper set".
        $sentinel = Invoke-GitConfigProcess -GitPath $gitPath -Argument @('config', '--list', '--show-origin')

        if (-not [string]::IsNullOrWhiteSpace($sentinel.Failure)) {
            $gitProblem = "$($sentinel.Failure), so the configuration was not read"
        } elseif ($null -eq $sentinel.ExitCode) {
            $gitProblem = 'git config --list reported no exit code, so the configuration was not read'
        } elseif ($sentinel.ExitCode -ne 0) {
            $gitProblem = "git config --list exited $($sentinel.ExitCode), so the configuration was not read"
        } elseif (@($sentinel.Output).Count -eq 0) {
            $gitProblem = 'git config --list printed no line, so an empty credential result would prove nothing'
        } else {
            # The pattern also matches helpers scoped to one URL.
            $probe = Invoke-GitConfigProcess -GitPath $gitPath -Argument @('config', '--show-origin', '--get-regexp', '^credential\..*helper$')
            $helper = @($probe.Output)

            if (-not [string]::IsNullOrWhiteSpace($probe.Failure)) {
                $gitProblem = "$($probe.Failure), so its credential helpers were not read"
            } elseif ($null -eq $probe.ExitCode) {
                $gitProblem = 'git config --get-regexp reported no exit code, so its credential helpers were not read'
            } elseif ($probe.ExitCode -eq 0 -and $helper.Count -eq 0) {
                $gitProblem = 'git config --get-regexp exited 0 without naming a key, so its credential helpers were not read'
            } elseif ($probe.ExitCode -eq 0) {
                # Only a line that carries an origin is a key line. A value that
                # spans lines continues without one, and a continuation line is
                # pure value, so it is dropped rather than parsed.
                $key = @($helper | ForEach-Object { Get-ConfigKeyName -Line $_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

                if ($key.Count -eq 0) {
                    $gitProblem = 'git config --get-regexp printed no line carrying an origin and a key, so its credential helpers were not read'
                } else {
                    foreach ($name in $key) {
                        $found.Add("git $(Format-RelayedText -Text $name)")
                    }
                }
            } elseif ($probe.ExitCode -eq 1) {
                # git exits 1 when no key matches, which is the clean case.
                $gitEvidence = "git ($gitPath) reports no credential helper, global or URL-scoped"
            } else {
                $gitProblem = "git config --get-regexp exited $($probe.ExitCode), so its credential helpers were not read"
            }
        }
    }

    if ($found.Count -gt 0 -or -not [string]::IsNullOrWhiteSpace($gitBreach)) {
        $part = [System.Collections.Generic.List[string]]::new()

        if ($found.Count -gt 0) {
            $part.Add('credential or proxy material present: ' + ($found -join ', '))
        }

        if (-not [string]::IsNullOrWhiteSpace($gitBreach)) {
            $part.Add($gitBreach)
        }

        if (-not [string]::IsNullOrWhiteSpace($gitProblem)) {
            $part.Add($gitProblem)
        }

        return New-CheckResult -Name 'CredentialAbsence' -Status 'Fail' -Evidence ($part -join '; ')
    }

    if (-not [string]::IsNullOrWhiteSpace($gitProblem)) {
        return New-CheckResult -Name 'CredentialAbsence' -Status 'Unavailable' -Evidence $gitProblem
    }

    return New-CheckResult -Name 'CredentialAbsence' -Status 'Pass' -Evidence ("none of $($variable -join ', ') is set, and $gitEvidence")
}

function Get-ConfigKeyName {
    <#
        The key and the file it came from, never the value. A credential helper
        value can be a shell snippet with a token in it, and this evidence is
        printed and written to a report.

        With --show-origin every key line begins with its origin and a tab. A
        line without one is the continuation of a value that spans lines, so it
        is pure value and this function returns nothing for it rather than
        guessing a key out of it.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Line
    )

    $separator = $Line.IndexOf("`t")

    if ($separator -lt 0) {
        return ''
    }

    $origin = $Line.Substring(0, $separator).Trim()
    $remainder = $Line.Substring($separator + 1)
    $space = $remainder.IndexOf(' ')
    $key = if ($space -ge 0) { $remainder.Substring(0, $space) } else { $remainder }
    $key = $key.Trim()

    if ([string]::IsNullOrWhiteSpace($key)) {
        $key = 'an unnamed credential key'
    }

    if ([string]::IsNullOrWhiteSpace($origin)) {
        return $key
    }

    return "$key ($origin)"
}

function Resolve-GitExecutable {
    <#
        git as an absolute path to an application, never as an alias, a
        function, or whatever PATH resolves to at the moment. Returns an empty
        string when it cannot be resolved, which the caller reports as
        unmeasured: "git is not installed" would let an empty PATH prove a
        clean machine.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $command = Get-Command -Name 'git' -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if ($null -eq $command) {
        return ''
    }

    $path = [string]$command.Source

    if ([string]::IsNullOrWhiteSpace($path) -or -not [System.IO.Path]::IsPathRooted($path)) {
        return ''
    }

    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return ''
    }

    return (Get-Item -LiteralPath $path -Force).FullName
}

function Get-ScrubbedGitEnvironment {
    <#
        The environment the git child is given. Every GIT_ variable and
        SSH_ASKPASS is dropped, because each can steer git at another
        configuration or at another askpass. XDG_CONFIG_HOME is dropped too:
        git reads the configuration under it instead of the one in the home
        folder, so a caller could point it at an empty folder and hide a helper.
        HOME and USERPROFILE are pinned to the operating system's own user
        profile folder, and on Windows PROGRAMDATA to its own common folder,
        which holds the machine-wide configuration, so that the measurement does
        not depend on where the caller started the verifier. The caller's own
        values are measured by name where they matter: the check fails when a
        steering variable is set.
        GIT_CONFIG_NOSYSTEM is deliberately not set: the system configuration
        is part of what a run would see, so it stays in scope.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $scrubbed = @{}

    foreach ($entry in [Environment]::GetEnvironmentVariables().GetEnumerator()) {
        $name = [string]$entry.Key

        if ($name -like 'GIT_*' -or $name -eq 'SSH_ASKPASS' -or $name -eq 'XDG_CONFIG_HOME') {
            continue
        }

        $scrubbed[$name] = [string]$entry.Value
    }

    $profileFolder = [Environment]::GetFolderPath('UserProfile')
    $scrubbed['HOME'] = $profileFolder
    $scrubbed['USERPROFILE'] = $profileFolder

    if ($script:OnWindows) {
        $scrubbed['PROGRAMDATA'] = [Environment]::GetFolderPath([System.Environment+SpecialFolder]::CommonApplicationData)
    }

    return $scrubbed
}

function Invoke-GitConfigProcess {
    <#
        Runs git as a child process with a scrubbed environment, a pinned
        working directory and a bounded run time, and reports what happened
        rather than what it hoped. A process that could not start, one that had
        to be killed, and one that returned no exit code are all failed
        measurements, never a clean result. The arguments are passed as a list,
        so nothing is re-quoted through a shell.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$GitPath,

        [Parameter(Mandatory)]
        [string[]]$Argument,

        [Parameter()]
        [int]$TimeoutMilliseconds = 10000
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $GitPath
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true
    $startInfo.WorkingDirectory = [Environment]::GetFolderPath('UserProfile')

    foreach ($value in $Argument) {
        $startInfo.ArgumentList.Add($value)
    }

    $startInfo.Environment.Clear()

    foreach ($entry in (Get-ScrubbedGitEnvironment).GetEnumerator()) {
        $startInfo.Environment[[string]$entry.Key] = [string]$entry.Value
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo

    try {
        try {
            $null = $process.Start()
        } catch {
            return @{ ExitCode = $null; Output = @(); TimedOut = $false; Failure = "git could not be started: $($_.Exception.Message)" }
        }

        # Both streams are drained before the wait, so a child that fills a pipe
        # cannot deadlock the measurement.
        $standardOutput = $process.StandardOutput.ReadToEndAsync()
        $standardError = $process.StandardError.ReadToEndAsync()

        if (-not $process.WaitForExit($TimeoutMilliseconds)) {
            try {
                $process.Kill($true)
            } catch {
                return @{ ExitCode = $null; Output = @(); TimedOut = $true; Failure = "git did not finish within $TimeoutMilliseconds ms and could not be killed: $($_.Exception.Message)" }
            }

            return @{ ExitCode = $null; Output = @(); TimedOut = $true; Failure = "git did not finish within $TimeoutMilliseconds ms" }
        }

        # The overload without a timeout waits for the redirected streams too.
        $process.WaitForExit()

        $text = $standardOutput.GetAwaiter().GetResult()
        $null = $standardError.GetAwaiter().GetResult()
        $line = @()

        if (-not [string]::IsNullOrEmpty($text)) {
            $line = @($text -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }

        return @{ ExitCode = $process.ExitCode; Output = $line; TimedOut = $false; Failure = '' }
    } finally {
        $process.Dispose()
    }
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

function Get-FirewallModuleProblem {
    <#
        Where the firewall cmdlets come from. They are resolved by name, so a module of the same name
        earlier on the module search path, a function, or an alias answers for the system's, and the
        outbound policy would be whatever whoever started this process arranged it to be. Each cmdlet
        must come from a module that lives under the system folder; anything else is unmeasured. The
        result is the reason, or nothing when all three do.

        A host that reaches NetSecurity through the Windows PowerShell compatibility layer resolves it
        to a proxy module outside the system folder and is reported the same way: the check does not
        pass until the module loads natively.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $system = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::System)

    if ([string]::IsNullOrWhiteSpace($system)) {
        return 'the system folder is not known, so the origin of the firewall cmdlets cannot be measured'
    }

    $prefix = [System.IO.Path]::TrimEndingDirectorySeparator($system) + [System.IO.Path]::DirectorySeparatorChar

    foreach ($name in @('Get-NetFirewallProfile', 'Get-NetFirewallRule', 'Get-NetFirewallSecurityFilter')) {
        $command = @(Get-Command -Name $name -ErrorAction SilentlyContinue)

        if ($command.Count -eq 0) {
            return "$name is unavailable, so the outbound policy cannot be measured"
        }

        $path = if ($null -ne $command[0].Module) { [string]$command[0].Module.Path } else { '' }

        if ([string]::IsNullOrEmpty($path)) {
            return "$name did not come from a module (it is a $($command[0].CommandType)), so something in this session outranks the one of the system"
        }

        if (-not $path.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            return "$name comes from $(Format-RelayedText -Text $path), not from a module under the system folder $system, so the firewall it reads is not shown to be the one of this machine"
        }
    }

    return $null
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
        rule harmless; so does one that names a well-known alias (WD, AU, BU),
        which is not resolved against the caller's token here.

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

        # A well-known alias such as WD, AU or BU names a group that is not resolved against the
        # caller's token here, and a principal that was not resolved never proves a rule harmless.
        if ($sid -notmatch '^S-1-\d+(-\d+)*$') {
            return $true
        }

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
        try {
            $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
            $listener.Start()
            $port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
        } catch {
            # Inside the outer try, so a listener that was constructed but could
            # not start is still released by the one finally below.
            return @{ Validated = $false; Detail = "no loopback listener could be opened: $($_.Exception.Message)" }
        }

        $outcome = Test-TcpEndpoint -Address '127.0.0.1' -Port $port -TimeoutMilliseconds $TimeoutMilliseconds

        if ($outcome.Outcome -eq 'Connected') {
            return @{ Validated = $true; Detail = "the probe reached a loopback listener on port $port" }
        }

        return @{ Validated = $false; Detail = "the loopback listener on port $port $($outcome.Detail)" }
    } catch {
        return @{ Validated = $false; Detail = "the loopback probe failed: $($_.Exception.Message)" }
    } finally {
        if ($null -ne $listener) {
            $listener.Stop()

            if ($listener -is [System.IDisposable]) {
                $listener.Dispose()
            }
        }
    }
}

function Test-PathInside {
    <#
        True when the path equals a root or lies inside one. Unlike Test-PathOverlap it does not
        count a path that merely contains a root: a folder wider than a declared root is not covered
        by the declaration.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$Root
    )

    $comparison = if ($script:OnWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    $separator = [string][System.IO.Path]::DirectorySeparatorChar
    $subject = [System.IO.Path]::TrimEndingDirectorySeparator([System.IO.Path]::GetFullPath($Path))

    foreach ($entry in @($Root | Where-Object -FilterScript { -not [string]::IsNullOrWhiteSpace($_) })) {
        $candidate = [System.IO.Path]::TrimEndingDirectorySeparator([System.IO.Path]::GetFullPath($entry))
        $candidatePrefix = if ($candidate.EndsWith($separator, $comparison)) { $candidate } else { $candidate + $separator }

        if ($subject.Equals($candidate, $comparison) -or $subject.StartsWith($candidatePrefix, $comparison)) {
            return $true
        }
    }

    return $false
}

function Get-EscapeSet {
    <#
        The places a run could use to get out of its declared roots: the user profile, the temp
        folder, the temp folder of the operating system, the folder that holds the profile, and the
        folders that hold the ledger sink and the chain head. The set is fixed and named so that what
        a Pass says is exact; it is not a search of the filesystem.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [string]$ProfilePath,

        [Parameter(Mandatory)]
        [string]$SinkPath,

        [Parameter(Mandatory)]
        [string]$ChainHeadPath
    )

    $osTemp = if ($script:OnWindows) {
        [System.IO.Path]::Combine([System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::LocalApplicationData), 'Temp')
    } else {
        '/tmp'
    }

    # GetTempPath follows the temp variables, which the caller sets, so the temp folder of the
    # operating system is named as well: a caller must not be able to move the temp folder out of
    # the set by pointing TEMP somewhere harmless.
    $candidate = @(
        [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile)
        [System.IO.Path]::GetTempPath()
        $osTemp
        [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($ProfilePath))
        [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($SinkPath))
        [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($ChainHeadPath))
    )

    $comparer = if ($script:OnWindows) { [System.StringComparer]::OrdinalIgnoreCase } else { [System.StringComparer]::Ordinal }
    $seen = [System.Collections.Generic.HashSet[string]]::new($comparer)
    $set = [System.Collections.Generic.List[string]]::new()

    foreach ($path in $candidate) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            continue
        }

        $normal = [System.IO.Path]::TrimEndingDirectorySeparator([System.IO.Path]::GetFullPath($path))

        if ($seen.Add($normal)) {
            $set.Add($normal)
        }
    }

    return $set.ToArray()
}

function Test-WritableRoot {
    <#
        What a Pass here says, and no more: every declared root is a directory this identity can add
        files and folders to, and none of the escape set is writable outside the declared roots. A
        place a declared root covers is not an escape; a place wider than a declared root is. On
        Windows rights are measured, not exercised, so the check creates nothing; elsewhere the
        measurement of a directory creates and removes a short-lived probe file in it. The filesystem
        is not enumerated: a writable path outside the declared roots and outside the escape set is
        not found by this check, and the filesystem policy of the deployment has to close it.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$Declared,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$EscapeSet
    )

    $root = @($Declared | Where-Object -FilterScript { -not [string]::IsNullOrWhiteSpace($_) })

    if ($root.Count -eq 0) {
        return New-CheckResult -Name 'WritableRoots' -Status 'Fail' -Evidence 'profile declares no writable root'
    }

    $unusable = [System.Collections.Generic.List[string]]::new()
    $unmeasured = [System.Collections.Generic.List[string]]::new()
    $escapable = [System.Collections.Generic.List[string]]::new()

    foreach ($declaredRoot in $root) {
        $object = Get-ObjectRight -Path $declaredRoot

        if ($object.State -eq 'Absent') {
            $unusable.Add("$declaredRoot (does not exist)")
            continue
        }

        if ($object.State -ne 'Measured') {
            $unmeasured.Add("$declaredRoot ($($object.Reason))")
            continue
        }

        if (-not $object.IsDirectory) {
            $unusable.Add("$declaredRoot (not a directory)")
            continue
        }

        $denied = @(@('WriteData', 'AppendData') | Where-Object -FilterScript { $object.Right[$_] -eq 'Denied' })
        $unknown = @(@('WriteData', 'AppendData') | Where-Object -FilterScript { $object.Right[$_] -eq 'Unknown' })

        if ($denied.Count -gt 0) {
            $lacking = ($denied | ForEach-Object -Process { $script:RightLabel[$_][1] }) -join ', '
            $unusable.Add("$declaredRoot (not writable: this identity lacks $lacking)")
        } elseif ($unknown.Count -gt 0) {
            $unmeasured.Add("$declaredRoot (could not measure " + (($unknown | ForEach-Object -Process { $script:RightLabel[$_][1] }) -join ', ') + ')')
        }
    }

    $escapeNote = [System.Collections.Generic.List[string]]::new()

    foreach ($escape in @($EscapeSet | Where-Object -FilterScript { -not [string]::IsNullOrWhiteSpace($_) })) {
        if (Test-PathInside -Path $escape -Root $root) {
            $escapeNote.Add("$escape (covered by a declared root)")
            continue
        }

        $object = Get-ObjectRight -Path $escape

        if ($object.State -eq 'Absent') {
            $escapeNote.Add("$escape (absent)")
            continue
        }

        if ($object.State -ne 'Measured') {
            $unmeasured.Add("$escape ($($object.Reason))")
            continue
        }

        $name = @('WriteData', 'AppendData', 'DeleteChild')
        $granted = @($name | Where-Object -FilterScript { $object.Right[$_] -eq 'Granted' })
        $unknown = @($name | Where-Object -FilterScript { $object.Right[$_] -eq 'Unknown' })

        if ($granted.Count -gt 0) {
            $escapable.Add("$escape (this identity holds " + (($granted | ForEach-Object -Process { $script:RightLabel[$_][[int]$object.IsDirectory] }) -join ', ') + ')')
        } elseif ($unknown.Count -gt 0) {
            $unmeasured.Add("$escape (could not measure " + (($unknown | ForEach-Object -Process { $script:RightLabel[$_][[int]$object.IsDirectory] }) -join ', ') + ')')
        } else {
            $escapeNote.Add("$escape (closed)")
        }
    }

    if ($unusable.Count -gt 0 -or $escapable.Count -gt 0) {
        $evidence = 'declared roots unusable: [' + ($unusable -join '; ') + ']; writable outside the declared roots: [' + ($escapable -join '; ') + ']'

        if ($unmeasured.Count -gt 0) {
            $evidence += '; not measurable: [' + ($unmeasured -join '; ') + ']'
        }

        return New-CheckResult -Name 'WritableRoots' -Status 'Fail' -Evidence $evidence
    }

    if ($unmeasured.Count -gt 0) {
        return New-CheckResult -Name 'WritableRoots' -Status 'Unavailable' -Evidence ('not measurable: ' + ($unmeasured -join '; '))
    }

    return New-CheckResult -Name 'WritableRoots' -Status 'Pass' -Evidence ("every declared root accepts new files and folders ($($root -join '; ')), and none of the escape set is writable outside them: $($escapeNote -join '; '); the rest of the filesystem is not enumerated")
}

function Test-LedgerProtection {
    <#
        The sink and the chain head are judged exactly like the pinned controls: by whether this
        identity can replace or loosen either file, the directory that holds it, or any directory
        above it, and whether either lies in or holds a writable root. A file that does not exist
        yet is closed only if nothing on the way lets this identity create it.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [string]$SinkPath,

        [Parameter(Mandatory)]
        [string]$ChainHeadPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$WritableRoot = @()
    )

    $violation = [System.Collections.Generic.List[string]]::new()
    $unmeasured = [System.Collections.Generic.List[string]]::new()
    $perPathLimit = 6

    foreach ($path in @($SinkPath, $ChainHeadPath)) {
        try {
            $protection = Test-PathProtection -Path $path -WritableRoot $WritableRoot
        } catch {
            $unmeasured.Add("${path}: $($_.Exception.Message)")
            continue
        }

        foreach ($line in @($protection.Violation | Select-Object -First $perPathLimit)) {
            $violation.Add($line)
        }

        if (@($protection.Violation).Count -gt $perPathLimit) {
            $violation.Add("${path}: and $(@($protection.Violation).Count - $perPathLimit) more breaches")
        }

        foreach ($line in @($protection.Unmeasured)) {
            $unmeasured.Add($line)
        }
    }

    if ($violation.Count -gt 0) {
        $evidence = 'this identity can replace or loosen: ' + ($violation -join '; ')

        if ($unmeasured.Count -gt 0) {
            $evidence += '; not measurable: ' + ($unmeasured -join '; ')
        }

        return New-CheckResult -Name 'LedgerProtection' -Status 'Fail' -Evidence $evidence
    }

    if ($unmeasured.Count -gt 0) {
        return New-CheckResult -Name 'LedgerProtection' -Status 'Unavailable' -Evidence ('not measurable: ' + ($unmeasured -join '; '))
    }

    return New-CheckResult -Name 'LedgerProtection' -Status 'Pass' -Evidence 'neither the sink nor the chain head, nor any directory above them, can be replaced or loosened by this identity'
}

function Test-ControlDigest {
    <#
        Each pinned control is hashed from one read of its bytes and compared as written: the
        profile's digests are validated lowercase, so a case difference is a mismatch, not a match.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        $ContainmentProfile
    )

    $present = @($ContainmentProfile.PSObject.Properties.Name)
    $problem = [System.Collections.Generic.List[string]]::new()

    foreach ($name in $script:PinnedControl) {
        if ($name -notin $present) {
            $problem.Add("$name is not declared")
            continue
        }

        $declaredPath = [string]$ContainmentProfile.$name.path

        if (-not (Test-Path -LiteralPath $declaredPath -PathType Leaf)) {
            $problem.Add("$name path does not exist")
            continue
        }

        try {
            $measured = Get-BytesDigest -Bytes ([System.IO.File]::ReadAllBytes($declaredPath))
        } catch {
            $problem.Add("$name could not be read: $($_.Exception.Message)")
            continue
        }

        if ($measured -cne [string]$ContainmentProfile.$name.sha256) {
            $problem.Add("$name digest is $measured but the profile pins $($ContainmentProfile.$name.sha256)")
        }
    }

    if ($problem.Count -gt 0) {
        return New-CheckResult -Name 'ControlDigest' -Status 'Fail' -Evidence ($problem -join '; ')
    }

    return New-CheckResult -Name 'ControlDigest' -Status 'Pass' -Evidence 'every pinned control matches its declared digest'
}

function Test-LiveArtifact {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        $ContainmentProfile,

        [Parameter(Mandatory)]
        [string]$LiveMode
    )

    $present = @($ContainmentProfile.PSObject.Properties.Name)
    $problem = [System.Collections.Generic.List[string]]::new()

    foreach ($name in $script:LiveControl) {
        if ($name -notin $present) {
            $problem.Add("live mode '$LiveMode' requires '$name' to be pinned in the profile")
            continue
        }

        $declaredPath = [string]$ContainmentProfile.$name.path

        if (-not (Test-Path -LiteralPath $declaredPath -PathType Leaf)) {
            $problem.Add("live artifact '$name' does not exist")
            continue
        }

        try {
            $measured = Get-BytesDigest -Bytes ([System.IO.File]::ReadAllBytes($declaredPath))
        } catch {
            $problem.Add("live artifact '$name' could not be read: $($_.Exception.Message)")
            continue
        }

        if ($measured -cne [string]$ContainmentProfile.$name.sha256) {
            $problem.Add("live artifact '$name' does not match its declared digest")
        }
    }

    if ($problem.Count -gt 0) {
        return New-CheckResult -Name 'LiveArtifacts' -Status 'Fail' -Evidence ($problem -join '; ')
    }

    return New-CheckResult -Name 'LiveArtifacts' -Status 'Pass' -Evidence "live artifacts are pinned and match for mode '$LiveMode'"
}

function Get-ContainmentCheckName {
    <#
        The one list of checks a run reports. A run that stops early reports the same names as one
        that completes, each marked not run, so a controller never has to guess what is missing.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [string]$LiveMode
    )

    $name = @(
        'VerifierBinding'
        'ControlDigest'
        'ControlImmutability'
        'IdentityBinding'
        'HookContract'
        'GrantRecorderUnregistered'
        'EgressPolicy'
        'RemoteUnreachable'
        'CredentialAbsence'
        'WritableRoots'
        'LedgerProtection'
    )

    if ($LiveMode -ne 'off') {
        $name += 'LiveArtifacts'
    }

    return $name
}

function Get-ContainmentCheck {
    <#
        Runs the measurements against a profile that already satisfies the schema. The order is part
        of the contract: the hook probe executes the pinned hook command as the identity that
        verifies, so it runs only after the verifier, the digests and the immutability of the
        controls it executes were measured and passed and that identity was bound to the role, since
        the immutability is measured for the identity that verifies and only the binding says
        whether that is the identity the profile names. Every other check is independent and always
        runs.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        $ContainmentProfile,

        [Parameter(Mandatory)]
        [string]$ProfilePath,

        [Parameter(Mandatory)]
        [ValidateSet('Controller', 'Worker')]
        [string]$Role,

        [Parameter(Mandatory)]
        [ValidateSet('off', 'read-only', 'disposable')]
        [string]$LiveMode,

        [Parameter(Mandatory)]
        [string]$VerifierPath
    )

    $check = [System.Collections.Generic.List[hashtable]]::new()
    $writableRoot = [string[]]@($ContainmentProfile.writableRoots)

    $check.Add((Test-VerifierBinding -ContainmentProfile $ContainmentProfile -ScriptPath $VerifierPath))
    $check.Add((Test-ControlDigest -ContainmentProfile $ContainmentProfile))
    $check.Add((Test-ControlImmutability -ProfilePath $ProfilePath -ContainmentProfile $ContainmentProfile -WritableRoot $writableRoot))
    $check.Add((Test-IdentityBinding -Role $Role -ControllerIdentity ([string]$ContainmentProfile.controllerIdentity) -WorkerIdentity ([string]$ContainmentProfile.workerIdentity)))

    $unmet = @(Get-GateFailure -Check @($check) -Require @('VerifierBinding', 'ControlDigest', 'ControlImmutability', 'IdentityBinding'))

    if ($unmet.Count -gt 0) {
        foreach ($notRun in @(Get-NotRunCheck -Name 'HookContract' -Reason "it executes the pinned hook command as this identity, which is trusted only after $($unmet -join ', ') passed")) {
            $check.Add($notRun)
        }
    } else {
        $check.Add((Test-HookContract `
                    -HookConfigPath ([string]$ContainmentProfile.hooksConfig.path) -HookConfigSha256 ([string]$ContainmentProfile.hooksConfig.sha256) `
                    -HookScriptPath ([string]$ContainmentProfile.hookScript.path) -HookScriptSha256 ([string]$ContainmentProfile.hookScript.sha256) `
                    -WritableRoot $writableRoot))
    }

    $check.Add((Test-GrantRecorderUnregistered -HookConfigPath ([string]$ContainmentProfile.hooksConfig.path) -HookConfigSha256 ([string]$ContainmentProfile.hooksConfig.sha256)))

    $declaredAllow = if ($Role -eq 'Controller') {
        @($ContainmentProfile.controllerEgressAllow)
    } else {
        @($ContainmentProfile.workerEgressAllow)
    }

    $check.Add((Test-EgressPolicy -DeclaredAllow ([string[]]$declaredAllow)))
    $check.Add((Test-RemoteUnreachable))

    # git is the third program the verifier runs as the identity it measures, and it is trusted on the
    # same four checks as the hook command: the variables are measured either way, git only after them.
    $gitGate = if ($unmet.Count -gt 0) { "$($unmet -join ', ') passed" } else { '' }
    $check.Add((Test-CredentialAbsence -WritableRoot $writableRoot -GitGateReason $gitGate))

    $escapeSet = @(Get-EscapeSet -ProfilePath $ProfilePath -SinkPath ([string]$ContainmentProfile.ledgerSink) -ChainHeadPath ([string]$ContainmentProfile.chainHead))
    $check.Add((Test-WritableRoot -Declared $writableRoot -EscapeSet $escapeSet))
    $check.Add((Test-LedgerProtection -SinkPath ([string]$ContainmentProfile.ledgerSink) -ChainHeadPath ([string]$ContainmentProfile.chainHead) -WritableRoot $writableRoot))

    if ($LiveMode -ne 'off') {
        $check.Add((Test-LiveArtifact -ContainmentProfile $ContainmentProfile -LiveMode $LiveMode))
    }

    return @($check)
}

function Get-ProtectedPath {
    <#
        Every file the verdict depends on, so that no operator-chosen output path can overwrite one.
        Read defensively: it runs before the profile is known to be valid.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $ContainmentProfile,

        [Parameter(Mandatory)]
        [string]$ProfilePath,

        [Parameter(Mandatory)]
        [string]$VerifierPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$ExtraPath = @()
    )

    $path = [System.Collections.Generic.List[string]]::new()
    $path.Add($ProfilePath)
    $path.Add($VerifierPath)

    foreach ($extra in @($ExtraPath)) {
        $path.Add([string]$extra)
    }

    if ($ContainmentProfile -is [System.Management.Automation.PSCustomObject]) {
        $field = $ContainmentProfile.PSObject.Properties

        foreach ($name in @($script:PinnedControl) + @($script:LiveControl)) {
            $entry = $field[$name]

            if ($null -ne $entry -and $entry.Value -is [System.Management.Automation.PSCustomObject]) {
                $declared = $entry.Value.PSObject.Properties['path']

                if ($null -ne $declared -and $declared.Value -is [string]) {
                    $path.Add($declared.Value)
                }
            }
        }

        foreach ($name in @('ledgerSink', 'chainHead')) {
            $entry = $field[$name]

            if ($null -ne $entry -and $entry.Value -is [string]) {
                $path.Add($entry.Value)
            }
        }

        $immutable = $field['immutableControlPaths']

        if ($null -ne $immutable) {
            foreach ($declared in @($immutable.Value)) {
                if ($declared -is [string]) {
                    $path.Add($declared)
                }
            }
        }
    }

    return [string[]]@($path | Where-Object -FilterScript { -not [string]::IsNullOrWhiteSpace($_) })
}

function Get-RevalidationCheckName {
    <#
        The one list of checks a revalidation reports, for the same reason Get-ContainmentCheckName is
        the one list for a verification: a run that stops early names what it did not run.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    return [string[]]@(
        'VerifierBinding'
        'ControlDigest'
        'ControlImmutability'
        'IdentityBinding'
        'LedgerChain'
        'FinalReport'
        'LedgerProtection'
    )
}

function Get-SinkSnapshot {
    <#
        The bytes of the ledger sink, and their SHA-256, as one read. The sink is opened the way the
        appender's own reader opens it: for reading, with every sharing mode allowed. The live
        appender holds the sink open for appending for the whole run, so a read that refused writers
        would collide with it and the ledger could never be revalidated, and a read that allows them
        blocks nobody. Whether the sink stayed the same while it was validated is decided by taking
        two snapshots and comparing their digests, not by holding the file.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $stream = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)

    try {
        $buffer = [System.IO.MemoryStream]::new()

        try {
            $stream.CopyTo($buffer)
            $bytes = $buffer.ToArray()
        } finally {
            $buffer.Dispose()
        }
    } finally {
        $stream.Dispose()
    }

    return [pscustomobject]@{
        Bytes = $bytes
        Sha256 = (Get-BytesDigest -Bytes $bytes)
    }
}

function Invoke-ChainValidation {
    <#
        Runs the pinned appender's profile-bound validation. The appender is run by the PowerShell
        that runs this verifier, not by whatever PATH names, with a time limit, and with its standard
        input closed so that nothing can wait for an answer.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$AppenderPath,

        [Parameter(Mandatory)]
        [string]$ProfilePath,

        [Parameter(Mandatory)]
        [string]$ProfileSha256,

        [Parameter()]
        [ValidateRange(1, 600)]
        [int]$TimeoutSecond = 60
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName

    foreach ($argument in @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $AppenderPath, '-Validate', '-ProfilePath', $ProfilePath, '-ProfileSha256', $ProfileSha256, '-RequireSealed')) {
        $startInfo.ArgumentList.Add($argument)
    }

    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = [System.Diagnostics.Process]::Start($startInfo)

    try {
        # Both streams are read while the appender runs: a full pipe would block it for good.
        $standardOutput = $process.StandardOutput.ReadToEndAsync()
        $standardError = $process.StandardError.ReadToEndAsync()
        $process.StandardInput.Close()

        if (-not $process.WaitForExit($TimeoutSecond * 1000)) {
            try {
                $process.Kill($true)
            } catch {
                Write-Verbose "could not stop the pinned appender: $($_.Exception.Message)"
            }

            throw "the pinned appender did not finish within $TimeoutSecond seconds"
        }

        $process.WaitForExit()

        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            Output = $standardOutput.GetAwaiter().GetResult().Trim()
            Error = $standardError.GetAwaiter().GetResult().Trim()
        }
    } finally {
        $process.Dispose()
    }
}

function Get-LedgerChainResult {
    <#
        What the pinned appender says about the ledger, held to the contract it is specified to
        keep: one JSON object that says the chain is valid from genesis, bound to the pinned profile
        and sealed. Anything else is a failure, and an appender that cannot be run is unmeasured. The
        summary is returned only for a chain that passed, so nothing downstream reads from one that
        did not.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$AppenderPath,

        [Parameter(Mandatory)]
        [string]$ProfilePath,

        [Parameter(Mandatory)]
        [string]$ProfileSha256
    )

    try {
        $run = Invoke-ChainValidation -AppenderPath $AppenderPath -ProfilePath $ProfilePath -ProfileSha256 $ProfileSha256
    } catch {
        return [pscustomobject]@{
            Check = (New-CheckResult -Name 'LedgerChain' -Status 'Unavailable' -Evidence "could not run the pinned appender: $($_.Exception.Message)")
            Summary = $null
        }
    }

    if ($run.ExitCode -ne 0) {
        $reason = if ([string]::IsNullOrWhiteSpace($run.Error)) { 'it gave no reason' } else { Format-RelayedText -Text ($run.Error -split "\r?\n")[0] }

        return [pscustomobject]@{
            Check = (New-CheckResult -Name 'LedgerChain' -Status 'Fail' -Evidence "the pinned appender refused the ledger (exit $($run.ExitCode)): $reason")
            Summary = $null
        }
    }

    try {
        $summary = $run.Output | ConvertFrom-Json -ErrorAction Stop
    } catch {
        $summary = $null
    }

    if ($summary -isnot [System.Management.Automation.PSCustomObject]) {
        return [pscustomobject]@{
            Check = (New-CheckResult -Name 'LedgerChain' -Status 'Fail' -Evidence 'the pinned appender wrote output that is not one JSON object')
            Summary = $null
        }
    }

    $problem = [System.Collections.Generic.List[string]]::new()
    $field = $summary.PSObject.Properties

    foreach ($name in @('valid', 'records', 'headSequence', 'sealed', 'headRecordSha256', 'bound')) {
        if ($null -eq $field[$name]) {
            $problem.Add("the summary lacks '$name'")
        }
    }

    if ($problem.Count -eq 0) {
        foreach ($name in @('valid', 'sealed', 'bound')) {
            if ($field[$name].Value -isnot [bool] -or -not $field[$name].Value) {
                $problem.Add("$name is not true")
            }
        }

        $records = $field['records'].Value

        if (($records -isnot [int] -and $records -isnot [long]) -or [long]$records -lt 1) {
            $problem.Add('records is not a positive count')
        }

        if ($field['headRecordSha256'].Value -isnot [string] -or $field['headRecordSha256'].Value -cnotmatch '^[0-9a-f]{64}$') {
            $problem.Add('headRecordSha256 is not a lowercase 64-hex digest')
        }
    }

    if ($problem.Count -gt 0) {
        return [pscustomobject]@{
            Check = (New-CheckResult -Name 'LedgerChain' -Status 'Fail' -Evidence ('the pinned appender did not report a valid, bound, sealed chain: ' + ($problem -join '; ')))
            Summary = $null
        }
    }

    return [pscustomobject]@{
        Check = (New-CheckResult -Name 'LedgerChain' -Status 'Pass' -Evidence "the pinned appender validated $($summary.records) records from genesis, bound to the pinned profile and sealed (head sequence $($summary.headSequence), head digest $($summary.headRecordSha256))")
        Summary = $summary
    }
}

function Test-FinalReport {
    <#
        The ledger must say that this report is the final one. Directly before the seal there is a
        FinalReport record whose data.sha256 is the digest of the report file, the seal chains to it,
        and the seal is the head the pinned appender validated. The records are read from the bytes
        of the sink the caller snapshotted around the validation, and tied to what the appender
        validated by their count and by the head digest. Digests are compared as written.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [byte[]]$SinkBytes,

        [Parameter(Mandatory)]
        [string]$FinalReportPath,

        [Parameter(Mandatory)]
        [AllowNull()]
        $ChainSummary
    )

    if ($null -eq $ChainSummary) {
        return New-CheckResult -Name 'FinalReport' -Status 'Unavailable' -Evidence 'there is no validated chain to read the final report record from'
    }

    if (-not (Test-Path -LiteralPath $FinalReportPath -PathType Leaf)) {
        return New-CheckResult -Name 'FinalReport' -Status 'Fail' -Evidence "the final report $FinalReportPath does not exist"
    }

    try {
        $reportDigest = Get-BytesDigest -Bytes ([System.IO.File]::ReadAllBytes($FinalReportPath))
    } catch {
        return New-CheckResult -Name 'FinalReport' -Status 'Unavailable' -Evidence "could not read the final report: $($_.Exception.Message)"
    }

    try {
        $text = [System.Text.UTF8Encoding]::new($false, $true).GetString($SinkBytes)
    } catch {
        return New-CheckResult -Name 'FinalReport' -Status 'Fail' -Evidence 'the ledger sink is not valid UTF-8'
    }

    $line = @($text -split "`n" | ForEach-Object -Process { $_.TrimEnd("`r") } | Where-Object -FilterScript { $_.Length -gt 0 })

    if ($line.Count -ne [long]$ChainSummary.records) {
        return New-CheckResult -Name 'FinalReport' -Status 'Fail' -Evidence "the ledger sink holds $($line.Count) records, but the pinned appender validated $($ChainSummary.records) records"
    }

    if ($line.Count -lt 2) {
        return New-CheckResult -Name 'FinalReport' -Status 'Fail' -Evidence 'a sealed ledger that records a final report holds at least a FinalReport record and the Seal'
    }

    try {
        $last = $line[-1] | ConvertFrom-Json -ErrorAction Stop
        $previous = $line[-2] | ConvertFrom-Json -ErrorAction Stop
    } catch {
        return New-CheckResult -Name 'FinalReport' -Status 'Fail' -Evidence 'one of the last two ledger records is not valid JSON'
    }

    $read = {
        param($Record, $Name)

        if ($Record -is [System.Management.Automation.PSCustomObject] -and $null -ne $Record.PSObject.Properties[$Name]) {
            return $Record.PSObject.Properties[$Name].Value
        }

        return $null
    }

    $problem = [System.Collections.Generic.List[string]]::new()
    $lastType = & $read $last 'type'
    $previousType = & $read $previous 'type'
    $recorded = & $read (& $read $previous 'data') 'sha256'

    $ordinal = [System.StringComparison]::Ordinal

    if (-not [string]::Equals([string]$lastType, 'Seal', $ordinal)) {
        $problem.Add("the last record is of type '$(Format-RelayedText -Text ([string]$lastType))', not Seal")
    }

    if (-not [string]::Equals([string](& $read $last 'recordSha256'), [string]$ChainSummary.headRecordSha256, $ordinal)) {
        $problem.Add("the last record's digest is not the head digest $($ChainSummary.headRecordSha256) the pinned appender validated")
    }

    if (-not [string]::Equals([string](& $read $last 'prevSha256'), [string](& $read $previous 'recordSha256'), $ordinal)) {
        $problem.Add('the seal does not chain to the record before it')
    }

    if (-not [string]::Equals([string]$previousType, 'FinalReport', $ordinal)) {
        $problem.Add("the record before the seal is of type '$(Format-RelayedText -Text ([string]$previousType))', not FinalReport")
    } elseif (-not [string]::Equals([string]$recorded, $reportDigest, $ordinal)) {
        $problem.Add("the ledger records the final report as $(Format-RelayedText -Text ([string]$recorded)), but $FinalReportPath hashes to $reportDigest")
    }

    if ($problem.Count -gt 0) {
        return New-CheckResult -Name 'FinalReport' -Status 'Fail' -Evidence ($problem -join '; ')
    }

    return New-CheckResult -Name 'FinalReport' -Status 'Pass' -Evidence "the Seal chains to the FinalReport record, which records $reportDigest, the digest of $FinalReportPath, and the Seal is the head the pinned appender validated"
}

function Get-RevalidationCheck {
    <#
        Runs the revalidation against a profile that already satisfies the schema. The pinned
        appender is executed as the identity that verifies, so it runs only after the verifier, the
        control digests, the immutability of the controls and the binding of that identity to the
        role were measured and passed, exactly like the hook probe. The sink
        is snapshotted before and after the appender validates it: a sink that changed in between
        was not the one that was validated, and fails the chain. The report is looked for only in a
        chain that validated, in the bytes of the second snapshot. The protection of the ledger is
        measured again whatever else happened.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        $ContainmentProfile,

        [Parameter(Mandatory)]
        [string]$ProfilePath,

        [Parameter(Mandatory)]
        [string]$ProfileSha256,

        [Parameter(Mandatory)]
        [ValidateSet('Controller', 'Worker')]
        [string]$Role,

        [Parameter(Mandatory)]
        [string]$VerifierPath,

        [Parameter(Mandatory)]
        [string]$FinalReportPath
    )

    $check = [System.Collections.Generic.List[hashtable]]::new()
    $writableRoot = [string[]]@($ContainmentProfile.writableRoots)
    $sinkPath = [string]$ContainmentProfile.ledgerSink

    $check.Add((Test-VerifierBinding -ContainmentProfile $ContainmentProfile -ScriptPath $VerifierPath))
    $check.Add((Test-ControlDigest -ContainmentProfile $ContainmentProfile))
    $check.Add((Test-ControlImmutability -ProfilePath $ProfilePath -ContainmentProfile $ContainmentProfile -WritableRoot $writableRoot))
    $check.Add((Test-IdentityBinding -Role $Role -ControllerIdentity ([string]$ContainmentProfile.controllerIdentity) -WorkerIdentity ([string]$ContainmentProfile.workerIdentity)))

    $unmet = @(Get-GateFailure -Check @($check) -Require @('VerifierBinding', 'ControlDigest', 'ControlImmutability', 'IdentityBinding'))

    if ($unmet.Count -gt 0) {
        foreach ($notRun in @(Get-NotRunCheck -Name @('LedgerChain', 'FinalReport') -Reason "the pinned appender is executed as this identity, and is trusted only after $($unmet -join ', ') passed")) {
            $check.Add($notRun)
        }
    } else {
        $before = $null
        $readProblem = $null

        try {
            $before = Get-SinkSnapshot -Path $sinkPath
        } catch {
            $readProblem = "could not read the ledger sink before it was validated: $($_.Exception.Message)"
        }

        if ($null -ne $readProblem -or $null -eq $before) {
            $check.Add((New-CheckResult -Name 'LedgerChain' -Status 'Unavailable' -Evidence $readProblem))

            foreach ($notRun in @(Get-NotRunCheck -Name @('FinalReport') -Reason 'the ledger sink could not be read, so no chain was validated')) {
                $check.Add($notRun)
            }
        } else {
            $chain = Get-LedgerChainResult -AppenderPath ([string]$ContainmentProfile.ledgerAppender.path) -ProfilePath $ProfilePath -ProfileSha256 $ProfileSha256
            $chainCheck = $chain.Check
            $after = $null

            if ($chainCheck.status -ceq 'Pass') {
                try {
                    $after = Get-SinkSnapshot -Path $sinkPath

                    if ($after.Sha256 -cne $before.Sha256) {
                        $chainCheck = New-CheckResult -Name 'LedgerChain' -Status 'Fail' -Evidence "the ledger sink changed while the pinned appender validated it (it hashed to $($before.Sha256) before and $($after.Sha256) after), so what was validated is not what was read"
                        $after = $null
                    }
                } catch {
                    $chainCheck = New-CheckResult -Name 'LedgerChain' -Status 'Unavailable' -Evidence "could not read the ledger sink after it was validated: $($_.Exception.Message)"
                    $after = $null
                }
            }

            $check.Add($chainCheck)

            if ($chainCheck.status -ceq 'Pass') {
                $check.Add((Test-FinalReport -SinkBytes $after.Bytes -FinalReportPath $FinalReportPath -ChainSummary $chain.Summary))
            } else {
                foreach ($notRun in @(Get-NotRunCheck -Name @('FinalReport') -Reason 'the ledger chain did not validate')) {
                    $check.Add($notRun)
                }
            }
        }
    }

    $check.Add((Test-LedgerProtection -SinkPath $sinkPath -ChainHeadPath ([string]$ContainmentProfile.chainHead) -WritableRoot $writableRoot))

    return @($check)
}

$mode = $PSCmdlet.ParameterSetName

# Before anything is measured, because what is measured is only as good as the functions and types
# that measure it. The call stack is read here, at script scope: inside a function it would be deeper.
$callStackDepth = @([System.Management.Automation.Runspaces.Runspace]::DefaultRunspace.Debugger.GetCallStack()).Count
$processProblem = & ${function:Get-FreshProcessProblem} -CommandLineArgument ([string[]][System.Environment]::GetCommandLineArgs()) -ScriptPath $PSCommandPath -CallStackDepth $callStackDepth

if ($processProblem) {
    [Console]::Error.WriteLine("Containment refused: $processProblem")
    exit 2
}

if ($mode -eq 'Verify' -and -not $Verify) {
    [Console]::Error.WriteLine('Containment verification requires -Verify.')
    exit 2
}

if ($mode -eq 'Revalidate' -and -not $Revalidate) {
    [Console]::Error.WriteLine('Containment revalidation requires -Revalidate.')
    exit 2
}

# The digest is the trust anchor, so it is compared exactly as the operator typed it. Folding its
# case first would accept a spelling the operator never wrote.
if ($ProfileSha256 -cnotmatch '^[0-9a-f]{64}$') {
    [Console]::Error.WriteLine('Containment refused: -ProfileSha256 must be a lowercase 64-hex digest.')
    exit 2
}

$canonicalFinalReportPath = $null

if ($mode -eq 'Revalidate') {
    if (-not [System.IO.Path]::IsPathFullyQualified($FinalReportPath)) {
        [Console]::Error.WriteLine('Containment refused: -FinalReportPath must be an absolute path.')
        exit 2
    }

    if (-not (Test-Path -LiteralPath $FinalReportPath -PathType Leaf)) {
        [Console]::Error.WriteLine("Containment refused: the final report '$FinalReportPath' does not exist.")
        exit 2
    }

    $canonicalFinalReportPath = (Resolve-Path -LiteralPath $FinalReportPath).ProviderPath
}

if (-not (Test-Path -LiteralPath $ProfilePath -PathType Leaf)) {
    [Console]::Error.WriteLine("Containment refused: profile '$ProfilePath' does not exist.")
    exit 2
}

$canonicalProfilePath = (Resolve-Path -LiteralPath $ProfilePath).ProviderPath

# One read: the bytes that are hashed are the bytes that are parsed.
try {
    $profileBytes = [System.IO.File]::ReadAllBytes($canonicalProfilePath)
} catch {
    [Console]::Error.WriteLine("Containment refused: profile '$canonicalProfilePath' cannot be read: $($_.Exception.Message)")
    exit 2
}

$measuredProfileDigest = Get-BytesDigest -Bytes $profileBytes

if ($measuredProfileDigest -cne $ProfileSha256) {
    [Console]::Error.WriteLine("Containment refused: profile digest $measuredProfileDigest does not match the direct argument.")
    exit 2
}

try {
    $containmentProfile = ConvertFrom-JsonByteArray -Bytes $profileBytes
} catch {
    [Console]::Error.WriteLine('Containment refused: profile is not valid JSON.')
    exit 2
}

# A report path is operator input. It is judged before anything is measured, against every file the
# verdict depends on, so it can never be the way a control is overwritten.
if (-not [string]::IsNullOrWhiteSpace($ReportPath)) {
    $reportProblem = Test-ReportPath -ReportPath $ReportPath -ProtectedPath @(Get-ProtectedPath -ContainmentProfile $containmentProfile -ProfilePath $canonicalProfilePath -VerifierPath $PSCommandPath -ExtraPath @($canonicalFinalReportPath))

    if ($reportProblem) {
        [Console]::Error.WriteLine("Containment refused: $reportProblem.")
        exit 2
    }
}

$check = [System.Collections.Generic.List[hashtable]]::new()
$check.Add((New-CheckResult -Name 'ProfileDigest' -Status 'Pass' -Evidence "profile matches the direct argument $measuredProfileDigest"))

# Wrapped because an empty result unwraps to $null and a single one to a scalar, and strict mode
# refuses .Count on either.
$schemaProblem = @(
    if ($containmentProfile -is [System.Management.Automation.PSCustomObject]) {
        Test-ProfileSchema -ContainmentProfile $containmentProfile
    } else {
        'the profile is not a JSON object'
    }
)

if ($schemaProblem.Count -gt 0) {
    $check.Add((New-CheckResult -Name 'ProfileSchema' -Status 'Fail' -Evidence ($schemaProblem -join '; ')))

    # Nothing the profile declares can be measured, and reading its fields would throw. Every
    # other check is named and reported as not run.
    $notRunName = if ($mode -eq 'Revalidate') { @(Get-RevalidationCheckName) } else { @(Get-ContainmentCheckName -LiveMode $LiveMode) }

    foreach ($notRun in @(Get-NotRunCheck -Name $notRunName -Reason 'the profile does not satisfy the schema, so nothing it declares can be measured')) {
        $check.Add($notRun)
    }
} else {
    $check.Add((New-CheckResult -Name 'ProfileSchema' -Status 'Pass' -Evidence 'closed schema satisfied and both egress lists are empty'))

    $measured = if ($mode -eq 'Revalidate') {
        Get-RevalidationCheck -ContainmentProfile $containmentProfile -ProfilePath $canonicalProfilePath -ProfileSha256 $ProfileSha256 -Role $Role -VerifierPath $PSCommandPath -FinalReportPath $canonicalFinalReportPath
    } else {
        Get-ContainmentCheck -ContainmentProfile $containmentProfile -ProfilePath $canonicalProfilePath -Role $Role -LiveMode $LiveMode -VerifierPath $PSCommandPath
    }

    foreach ($result in @($measured)) {
        $check.Add($result)
    }
}

$outcome = Get-Verdict -Check @($check)
$blocking = @($outcome.Blocking)
$verdict = $outcome.Verdict

$report = [ordered]@{
    verdict = $verdict
    mode = $mode
    role = $Role
}

if ($mode -eq 'Revalidate') {
    $report['finalReportPath'] = $canonicalFinalReportPath
} else {
    $report['liveMode'] = $LiveMode
}

$report['profilePath'] = $canonicalProfilePath
$report['profileSha256'] = $measuredProfileDigest
$report['measuredUtc'] = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$report['checks'] = @($check)

if (-not [string]::IsNullOrWhiteSpace($ReportPath)) {
    try {
        $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
    } catch {
        [Console]::Error.WriteLine("Containment refused: the report could not be written to '$ReportPath': $($_.Exception.Message)")
        exit 2
    }
}

foreach ($result in $blocking) {
    [Console]::Error.WriteLine("Containment $($result.status): $($result.name) - $($result.evidence)")
}

if ($verdict -eq 'Pass') {
    if ($mode -eq 'Revalidate') {
        Write-Output "Ledger and final report revalidated for $Role with $($check.Count) checks passed."
    } else {
        Write-Output "Containment verified for $Role with $($check.Count) checks passed."
    }

    exit 0
}

if ($mode -eq 'Revalidate') {
    Write-Output "Ledger and final report NOT revalidated for ${Role}: $($blocking.Count) of $($check.Count) checks did not pass."
} else {
    Write-Output "Containment NOT verified for ${Role}: $($blocking.Count) of $($check.Count) checks did not pass."
}

exit 2
