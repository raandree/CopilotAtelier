#requires -Version 5.1
Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------------------------
# Capture a window that is ALREADY OPEN and owned by the user.
#
# Sibling of DialogCapture.ps1, with the opposite lifecycle contract: that helper owns a process
# it started and may close it; this one must never launch, close, or kill anything. It implements
# the "attempt, validate, then escalate" ladder from ../SKILL.md, section "Step 2 - Apply the
# GPU-composited rule", so a composited top-level frame (a browser window) is captured by the
# cheap path when that works and by a composited desktop read when it does not.
# ---------------------------------------------------------------------------------------------

function Initialize-OpenWindowCapture {
    [CmdletBinding()]
    param()

    # A distinct type name from GuiDoc.WindowCapture: both helpers can be dot-sourced into one
    # session, and a loaded type cannot be redefined.
    if (-not ('GuiDoc.OpenWindowCapture' -as [type])) {
        Add-Type -Namespace 'GuiDoc' -Name 'OpenWindowCapture' -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true)]
public static extern bool GetWindowRect(System.IntPtr hWnd, out RECT lpRect);

[System.Runtime.InteropServices.DllImport("dwmapi.dll")]
public static extern int DwmGetWindowAttribute(System.IntPtr hWnd, int attribute, out RECT value, int size);

[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool PrintWindow(System.IntPtr hWnd, System.IntPtr hdcBlt, uint nFlags);

[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool IsWindow(System.IntPtr hWnd);

[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool IsIconic(System.IntPtr hWnd);

[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);

[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool SetForegroundWindow(System.IntPtr hWnd);

[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern uint GetWindowThreadProcessId(System.IntPtr hWnd, out uint lpdwProcessId);

[System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true)]
public static extern bool SetProcessDpiAwarenessContext(System.IntPtr value);

public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
'@
    }
}

function Confirm-OpenWindowOwnership {
    <#
    .SYNOPSIS
        Verifies that a window handle still belongs to the expected process.

    .PARAMETER Process
        The process the caller resolved the window from. Never adopted from a title match.

    .PARAMETER Handle
        The top-level window handle to verify.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Diagnostics.Process]$Process,

        [Parameter(Mandatory)]
        [System.IntPtr]$Handle
    )

    Initialize-OpenWindowCapture

    if ($Process.HasExited) {
        throw "The target process has exited: $($Process.Id)."
    }

    if (-not [GuiDoc.OpenWindowCapture]::IsWindow($Handle)) {
        throw "The window handle is no longer valid: $Handle."
    }

    $windowProcessId = [uint32]0
    $null = [GuiDoc.OpenWindowCapture]::GetWindowThreadProcessId($Handle, [ref]$windowProcessId)

    if ($windowProcessId -ne $Process.Id) {
        throw "Window $Handle belongs to process $windowProcessId, not $($Process.Id)."
    }
}

function Test-WindowCaptureContent {
    <#
    .SYNOPSIS
        Rejects a uniform or predominantly black capture.

    .DESCRIPTION
        PrintWindow can return $true for an unpainted frame, so the pixels themselves are the
        gate. Raise MaximumDarkRatio for a legitimately dark-theme target: a universal black
        threshold rejects valid dark screenshots.

    .PARAMETER Bitmap
        The captured bitmap to sample.

    .PARAMETER MinimumDistinctColor
        Distinct sampled colours required before the frame counts as painted.

    .PARAMETER MaximumDarkRatio
        Highest tolerated fraction of near-black samples.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Drawing.Bitmap]$Bitmap,

        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$MinimumDistinctColor = 24,

        [Parameter()]
        [ValidateRange(0.0, 1.0)]
        [double]$MaximumDarkRatio = 0.5
    )

    $distinctColor = [System.Collections.Generic.HashSet[int]]::new()
    $darkSample = 0
    $sample = 0

    for ($x = 4; $x -lt $Bitmap.Width; $x += 17) {
        for ($y = 4; $y -lt $Bitmap.Height; $y += 17) {
            $pixel = $Bitmap.GetPixel($x, $y)
            $null = $distinctColor.Add($pixel.ToArgb())

            if (($pixel.R + $pixel.G + $pixel.B) -lt 24) {
                $darkSample++
            }

            $sample++
        }
    }

    if ($sample -eq 0) {
        return $false
    }

    $darkRatio = $darkSample / $sample
    Write-Verbose "Samples=$sample DistinctColors=$($distinctColor.Count) DarkRatio=$([math]::Round($darkRatio, 4))"

    return ($distinctColor.Count -ge $MinimumDistinctColor -and $darkRatio -lt $MaximumDarkRatio)
}

function Get-WindowFrameRectangle {
    <#
    .SYNOPSIS
        Reads a window's visible frame, excluding the invisible DWM resize border.

    .PARAMETER Handle
        The top-level window handle to measure.
    #>
    [CmdletBinding()]
    [OutputType([GuiDoc.OpenWindowCapture+RECT])]
    param(
        [Parameter(Mandatory)]
        [System.IntPtr]$Handle
    )

    Initialize-OpenWindowCapture

    $bounds = New-Object 'GuiDoc.OpenWindowCapture+RECT'

    # DWMWA_EXTENDED_FRAME_BOUNDS (9); GetWindowRect would add the invisible resize border.
    $dwmResult = [GuiDoc.OpenWindowCapture]::DwmGetWindowAttribute(
        $Handle,
        9,
        [ref]$bounds,
        [System.Runtime.InteropServices.Marshal]::SizeOf($bounds)
    )

    if ($dwmResult -ne 0) {
        Write-Verbose "DwmGetWindowAttribute returned $dwmResult; falling back to GetWindowRect."

        if (-not [GuiDoc.OpenWindowCapture]::GetWindowRect($Handle, [ref]$bounds)) {
            throw "Could not read the bounds of window $Handle."
        }
    }

    if (($bounds.Right - $bounds.Left) -le 0 -or ($bounds.Bottom - $bounds.Top) -le 0) {
        throw "Window $Handle reported an empty rectangle."
    }

    $bounds
}

function Save-OpenWindowCapture {
    <#
    .SYNOPSIS
        Captures a window that is already open to a PNG, without launching or closing anything.

    .DESCRIPTION
        Applies the SKILL.md Step 2 ladder: PrintWindow with PW_RENDERFULLCONTENT first, pixel
        validation, then a composited desktop read through CopyFromScreen. Restores a window it
        un-minimized and never terminates the target, which is user-owned.

        The screen fallback copies whatever occupies those pixels, so it needs the window
        restored and unobscured. Review the result before sharing it.

    .PARAMETER Process
        The process that owns the window. Ownership is re-checked against the handle.

    .PARAMETER Handle
        The top-level window handle to capture.

    .PARAMETER Path
        Destination PNG path. Missing parent folders are created.

    .PARAMETER MaximumDarkRatio
        Passed to Test-WindowCaptureContent. Raise it for a dark-theme target.

    .EXAMPLE
        $edge = Get-Process msedge | Where-Object MainWindowTitle -match 'WELT'
        Save-OpenWindowCapture -Process $edge -Handle $edge.MainWindowHandle -Path "$env:TEMP\edge.png"
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Diagnostics.Process]$Process,

        [Parameter(Mandatory)]
        [System.IntPtr]$Handle,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter()]
        [ValidateRange(0.0, 1.0)]
        [double]$MaximumDarkRatio = 0.5
    )

    Initialize-OpenWindowCapture
    Add-Type -AssemblyName System.Drawing
    Confirm-OpenWindowOwnership -Process $Process -Handle $Handle

    # DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 (-4): without it a virtualized host reads
    # scaled bounds and the screen fallback lands on the wrong pixels. Fails harmlessly when
    # awareness is already set by the host.
    try {
        $null = [GuiDoc.OpenWindowCapture]::SetProcessDpiAwarenessContext([System.IntPtr]::new(-4))
    }
    catch {
        Write-Verbose "Could not set DPI awareness: $($_.Exception.Message)"
    }

    $wasMinimized = [GuiDoc.OpenWindowCapture]::IsIconic($Handle)
    $bitmap = $null
    $graphics = $null

    try {
        if ($wasMinimized) {
            $null = [GuiDoc.OpenWindowCapture]::ShowWindow($Handle, 9)   # SW_RESTORE
        }

        $null = [GuiDoc.OpenWindowCapture]::SetForegroundWindow($Handle)

        $bounds = Get-WindowFrameRectangle -Handle $Handle
        $width = $bounds.Right - $bounds.Left
        $height = $bounds.Bottom - $bounds.Top

        $bitmap = [System.Drawing.Bitmap]::new(
            $width,
            $height,
            [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
        )
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)

        $deviceContext = $graphics.GetHdc()
        try {
            # PW_RENDERFULLCONTENT (0x2): required for a composited frame, still not a guarantee.
            $printed = [GuiDoc.OpenWindowCapture]::PrintWindow($Handle, $deviceContext, [uint32]2)
        }
        finally {
            $graphics.ReleaseHdc($deviceContext)
        }

        $method = 'PrintWindow'
        $contentParameters = @{
            Bitmap           = $bitmap
            MaximumDarkRatio = $MaximumDarkRatio
        }

        if (-not $printed -or -not (Test-WindowCaptureContent @contentParameters)) {
            Write-Verbose 'PrintWindow failed its content gate; reading the composited desktop.'

            $graphics.CopyFromScreen(
                $bounds.Left,
                $bounds.Top,
                0,
                0,
                $bitmap.Size,
                [System.Drawing.CopyPixelOperation]::SourceCopy
            )
            $method = 'CopyFromScreen'

            if (-not (Test-WindowCaptureContent @contentParameters)) {
                throw "Both capture paths produced an unpainted image for window $Handle."
            }
        }

        $directory = Split-Path -Path $Path -Parent
        if ($directory -and -not (Test-Path -LiteralPath $directory)) {
            $null = New-Item -ItemType Directory -Path $directory -Force
        }

        $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)

        [pscustomobject]@{
            Path   = $Path
            Width  = $width
            Height = $height
            Method = $method
        }
    }
    finally {
        if ($graphics) { $graphics.Dispose() }
        if ($bitmap) { $bitmap.Dispose() }

        # Restore only what this helper changed; the process stays untouched.
        if ($wasMinimized -and [GuiDoc.OpenWindowCapture]::IsWindow($Handle)) {
            $null = [GuiDoc.OpenWindowCapture]::ShowWindow($Handle, 6)   # SW_MINIMIZE
        }
    }
}
