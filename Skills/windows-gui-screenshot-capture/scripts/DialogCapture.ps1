#requires -Version 5.1
Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------------------------
# Origin: copied verbatim from the GUI-screenshot-docs proof-of-concept at
#   D:\guitest\src\Common\DialogCapture.ps1
# Ready-to-use, framework-agnostic native-window capture helpers (FindWindow + PrintWindow +
# PostMessage). Dot-source it from any WPF / WinForms / Win32 capture script to grab a native
# dialog (e.g. a MessageBox, window class #32770). See ../SKILL.md, section
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

[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern System.IntPtr GetForegroundWindow();

[System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Auto, SetLastError = true)]
public static extern System.IntPtr FindWindow(string lpClassName, string lpWindowName);

[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool PrintWindow(System.IntPtr hwnd, System.IntPtr hdcBlt, uint nFlags);

[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern System.IntPtr PostMessage(System.IntPtr hWnd, uint msg, System.IntPtr wParam, System.IntPtr lParam);

public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
'@
    }
}

function Get-ForegroundWindowHandle {
    [CmdletBinding()]
    [OutputType([System.IntPtr])]
    param()

    Initialize-WindowCapture
    [GuiDoc.WindowCapture]::GetForegroundWindow()
}

function Get-DialogWindowHandle {
    [CmdletBinding()]
    [OutputType([System.IntPtr])]
    param(
        [Parameter(Mandatory)]
        [string]$ClassName,

        [Parameter(Mandatory)]
        [string]$Title
    )

    Initialize-WindowCapture
    [GuiDoc.WindowCapture]::FindWindow($ClassName, $Title)
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
        [System.IntPtr]$Handle,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    Initialize-WindowCapture
    Add-Type -AssemblyName System.Drawing

    $rect = New-Object 'GuiDoc.WindowCapture+RECT'
    [void][GuiDoc.WindowCapture]::GetWindowRect($Handle, [ref]$rect)
    $width  = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top
    if ($width -le 0 -or $height -le 0) {
        throw "Window ($Handle) has no visible area to capture."
    }

    $bitmap = [System.Drawing.Bitmap]::new($width, $height)
    try {
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            $hdc = $graphics.GetHdc()
            try {
                # PW_RENDERFULLCONTENT (0x2) captures the window even if it is not on top.
                [void][GuiDoc.WindowCapture]::PrintWindow($Handle, $hdc, [uint32]2)
            }
            finally {
                $graphics.ReleaseHdc($hdc)
            }
        }
        finally {
            $graphics.Dispose()
        }

        $dir = Split-Path -Path $Path -Parent
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $bitmap.Dispose()
    }

    Write-Verbose "Saved window screenshot: $Path"
    $Path
}

function Send-WindowClose {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.IntPtr]$Handle
    )

    Initialize-WindowCapture
    $WM_CLOSE = [uint32]0x0010
    [void][GuiDoc.WindowCapture]::PostMessage($Handle, $WM_CLOSE, [System.IntPtr]::Zero, [System.IntPtr]::Zero)
}
