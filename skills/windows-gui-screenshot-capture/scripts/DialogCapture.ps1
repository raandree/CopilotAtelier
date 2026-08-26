#requires -Version 5.1
Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------------------------
# Origin: adapted from the GUI-screenshot-docs proof-of-concept at
#   D:\guitest\src\Common\DialogCapture.ps1
# Ready-to-use, framework-agnostic native-window capture helpers (process-scoped EnumWindows +
# PrintWindow + PostMessage). Dot-source it from any WPF / WinForms / Win32 capture script to grab
# a native dialog (e.g. a MessageBox, window class #32770). See ../SKILL.md, section
# "Step 5 - Capture native dialogs", for the capture-then-dismiss timer pattern.
# ---------------------------------------------------------------------------------------------

# Shared native-window capture helpers used by every UI-framework demo (WPF, WinForms, ...).
# These rely only on Win32 (user32) plus System.Drawing, loaded lazily, so dot-sourcing this
# file has no dependency on any specific UI framework. Framework-specific in-process capture
# (WPF RenderTargetBitmap, WinForms DrawToBitmap) lives in each framework folder's Capture.ps1.

# --- Native window capture -------------------------------------------------------------------
# Used for capturing native dialogs (e.g. a MessageBox), which are separate OS windows and so
# cannot be rendered with RenderTargetBitmap. These helpers load their dependencies lazily so
# that dot-sourcing this file never affects normal (interactive) application startup.

function Initialize-WindowCapture {
    [CmdletBinding()]
    param()

    if (-not ('GuiDoc.WindowCapture' -as [type])) {
        Add-Type -Namespace 'GuiDoc' -Name 'WindowCapture' -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool GetWindowRect(System.IntPtr hWnd, out RECT lpRect);

public delegate bool EnumWindowsProc(System.IntPtr hWnd, System.IntPtr lParam);

[System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true)]
public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, System.IntPtr lParam);

[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern uint GetWindowThreadProcessId(System.IntPtr hWnd, out uint lpdwProcessId);

[System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern int GetClassName(System.IntPtr hWnd, System.Text.StringBuilder lpClassName, int nMaxCount);

[System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern int GetWindowText(System.IntPtr hWnd, System.Text.StringBuilder lpString, int nMaxCount);

[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern System.IntPtr GetWindow(System.IntPtr hWnd, uint uCmd);

[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool IsWindow(System.IntPtr hWnd);

public static System.IntPtr[] FindWindowsForProcess(
    uint processId,
    string className,
    string title,
    System.IntPtr ownerHandle)
{
    var matchingHandles = new System.Collections.Generic.List<System.IntPtr>();
    EnumWindowsProc callback = delegate(System.IntPtr candidateHandle, System.IntPtr callbackParameter)
    {
        uint candidateProcessId;
        GetWindowThreadProcessId(candidateHandle, out candidateProcessId);
        if (candidateProcessId != processId)
        {
            return true;
        }

        var classBuilder = new System.Text.StringBuilder(256);
        GetClassName(candidateHandle, classBuilder, classBuilder.Capacity);
        if (classBuilder.ToString() != className)
        {
            return true;
        }

        var titleBuilder = new System.Text.StringBuilder(512);
        GetWindowText(candidateHandle, titleBuilder, titleBuilder.Capacity);
        if (titleBuilder.ToString() != title)
        {
            return true;
        }

        if (ownerHandle != System.IntPtr.Zero && GetWindow(candidateHandle, 4) != ownerHandle)
        {
            return true;
        }

        matchingHandles.Add(candidateHandle);
        return true;
    };

    if (!EnumWindows(callback, System.IntPtr.Zero))
    {
        throw new System.ComponentModel.Win32Exception(
            System.Runtime.InteropServices.Marshal.GetLastWin32Error(),
            "EnumWindows could not enumerate top-level windows."
        );
    }

    System.GC.KeepAlive(callback);
    return matchingHandles.ToArray();
}

[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool PrintWindow(System.IntPtr hwnd, System.IntPtr hdcBlt, uint nFlags);

[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool PostMessage(System.IntPtr hWnd, uint msg, System.IntPtr wParam, System.IntPtr lParam);

public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
'@
    }
}

function Confirm-WindowOwnership {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Diagnostics.Process]$Process,

        [Parameter(Mandatory)]
        [System.IntPtr]$Handle
    )

    Initialize-WindowCapture
    if ($Process.HasExited) {
        throw "The process started for capture has already exited: $($Process.Id)."
    }

    if (-not [GuiDoc.WindowCapture]::IsWindow($Handle)) {
        throw "The window handle is no longer valid: $Handle."
    }

    $windowProcessId = [uint32]0
    $null = [GuiDoc.WindowCapture]::GetWindowThreadProcessId(
        $Handle,
        [ref]$windowProcessId
    )
    if ($windowProcessId -ne $Process.Id) {
        throw "Window $Handle belongs to process $windowProcessId, not started process $($Process.Id)."
    }
}

function Get-DialogWindowHandle {
    [CmdletBinding()]
    [OutputType([System.IntPtr])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Diagnostics.Process]$Process,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ClassName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Title,

        [Parameter()]
        [System.IntPtr]$OwnerHandle = [System.IntPtr]::Zero
    )

    Initialize-WindowCapture
    if ($Process.HasExited) {
        throw "The process started for capture has already exited: $($Process.Id)."
    }

    $matchingHandles = [GuiDoc.WindowCapture]::FindWindowsForProcess(
        [uint32]$Process.Id,
        $ClassName,
        $Title,
        $OwnerHandle
    )

    if ($matchingHandles.Count -gt 1) {
        throw "Found $($matchingHandles.Count) matching '$Title' windows in process $($Process.Id)."
    }

    if ($matchingHandles.Count -eq 1) {
        return $matchingHandles[0]
    }

    [System.IntPtr]::Zero
}

function Save-WindowImage {
    <#
    .SYNOPSIS
        Captures a native window (by handle) to a PNG using an on-screen copy.

    .DESCRIPTION
        Reads the window's physical bounds with GetWindowRect (DPI-correct) and captures the
        window with PrintWindow (PW_RENDERFULLCONTENT), which works even when the window is not
        on top. Used for native dialogs that RenderTargetBitmap cannot reach.

    .PARAMETER Handle
        The native window handle (HWND) to capture.

    .PARAMETER Path
        Destination PNG file path. Missing parent folders are created automatically.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Diagnostics.Process]$Process,

        [Parameter(Mandatory)]
        [System.IntPtr]$Handle,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    Initialize-WindowCapture
    Add-Type -AssemblyName System.Drawing
    Confirm-WindowOwnership -Process $Process -Handle $Handle

    $rectangle = New-Object 'GuiDoc.WindowCapture+RECT'
    $boundsRead = [GuiDoc.WindowCapture]::GetWindowRect(
        $Handle,
        [ref]$rectangle
    )
    if (-not $boundsRead) {
        throw "GetWindowRect could not read window $Handle."
    }

    $width = $rectangle.Right - $rectangle.Left
    $height = $rectangle.Bottom - $rectangle.Top
    if ($width -le 0 -or $height -le 0) {
        throw "Window ($Handle) has no visible area to capture."
    }

    $bitmap = [System.Drawing.Bitmap]::new($width, $height)
    try {
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            $deviceContext = $graphics.GetHdc()
            try {
                # PW_RENDERFULLCONTENT (0x2) captures the window even if it is not on top.
                $captured = [GuiDoc.WindowCapture]::PrintWindow(
                    $Handle,
                    $deviceContext,
                    [uint32]2
                )
                if (-not $captured) {
                    throw "PrintWindow could not capture window $Handle."
                }
            }
            finally {
                $graphics.ReleaseHdc($deviceContext)
            }
        }
        finally {
            $graphics.Dispose()
        }

        $directory = Split-Path -Path $Path -Parent
        if ($directory -and -not (Test-Path -LiteralPath $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $bitmap.Dispose()
    }

    Write-Verbose "Saved window screenshot: $Path"
    $Path
}

function Invoke-WindowCloseMessage {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [System.IntPtr]$Handle
    )

    Initialize-WindowCapture
    $windowCloseMessage = [uint32]0x0010
    [GuiDoc.WindowCapture]::PostMessage(
        $Handle,
        $windowCloseMessage,
        [System.IntPtr]::Zero,
        [System.IntPtr]::Zero
    )
}

function Send-WindowClose {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Diagnostics.Process]$Process,

        [Parameter(Mandatory)]
        [System.IntPtr]$Handle
    )

    Initialize-WindowCapture
    Confirm-WindowOwnership -Process $Process -Handle $Handle
    if ($PSCmdlet.ShouldProcess("Window $Handle in process $($Process.Id)", 'Post WM_CLOSE')) {
        $posted = Invoke-WindowCloseMessage -Handle $Handle
        if (-not $posted) {
            throw "PostMessage could not close window $Handle."
        }
    }
}
