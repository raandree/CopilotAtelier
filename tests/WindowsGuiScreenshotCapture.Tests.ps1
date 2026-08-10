BeforeDiscovery {
    <#
        The helper compiles Win32 interop, so it is bound to Windows and to
        PowerShell 7. A #requires statement cannot express that: it fails
        discovery on Windows PowerShell 5.1 instead of skipping, which fails the
        whole run.
    #>
    $script:isSupportedHost = (
        [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT -and
        $PSVersionTable.PSVersion.Major -ge 7
    )
}

Describe 'Windows GUI screenshot native-dialog helper' -Tag 'Unit' -Skip:(-not $script:isSupportedHost) {
    BeforeAll {
        $script:helperPath = Join-Path $PSScriptRoot (
            '..\Skills\windows-gui-screenshot-capture\scripts\DialogCapture.ps1'
        )
        . $script:helperPath
        $script:helperContent = Get-Content -LiteralPath $script:helperPath -Raw -Encoding UTF8
    }

    It 'Should compile the Win32 interop type' {
        { Initialize-WindowCapture } | Should -Not -Throw
    }

    It 'Should declare PostMessage with its native Boolean return type' {
        Initialize-WindowCapture

        [GuiDoc.WindowCapture].GetMethod('PostMessage').ReturnType |
            Should -Be ([bool])
    }

    It 'Should require the started Process when locating a dialog' {
        $command = Get-Command -Name Get-DialogWindowHandle

        $command.Parameters.ContainsKey('Process') | Should -BeTrue
        $command.Parameters.Process.ParameterType |
            Should -Be ([System.Diagnostics.Process])
    }

    It 'Should require the started Process before closing a window' {
        $command = Get-Command -Name Send-WindowClose

        $command.Parameters.ContainsKey('Process') | Should -BeTrue
        $command.Parameters.Process.ParameterType |
            Should -Be ([System.Diagnostics.Process])
    }

    It 'Should require the started Process before capturing a window' {
        $command = Get-Command -Name Save-WindowImage

        $command.Parameters.ContainsKey('Process') | Should -BeTrue
        $command.Parameters.Process.ParameterType |
            Should -Be ([System.Diagnostics.Process])
    }

    It 'Should not expose foreground-window discovery' {
        Get-Command -Name Get-ForegroundWindowHandle -ErrorAction SilentlyContinue |
            Should -BeNullOrEmpty
        $script:helperContent | Should -Not -Match 'GetForegroundWindow\('
    }

    It 'Should enumerate process-owned windows instead of using global FindWindow' {
        $script:helperContent | Should -Match 'EnumWindows\('
        $script:helperContent |
            Should -Not -Match 'public static extern System\.IntPtr FindWindow\('
    }

    It 'Should fail when GetWindowRect cannot read the window bounds' {
        $script:helperContent | Should -Match '\$boundsRead\s*=.*GetWindowRect'
        $script:helperContent | Should -Match 'if\s*\(-not\s+\$boundsRead\)'
    }

    It 'Should fail when PrintWindow does not capture the window' {
        $script:helperContent | Should -Match '\$captured\s*=.*PrintWindow'
        $script:helperContent | Should -Match 'if\s*\(-not\s+\$captured\)'
    }

    It 'Should fail when PostMessage cannot close the window' {
        Mock -CommandName Confirm-WindowOwnership
        Mock -CommandName Invoke-WindowCloseMessage -MockWith { $false }

        $process = Get-Process -Id $PID
        $closeParameters = @{
            Process = $process
            Handle  = [System.IntPtr]123
            Confirm = $false
        }
        { Send-WindowClose @closeParameters } |
            Should -Throw -ExpectedMessage '*PostMessage could not close*'

        Should -Invoke -CommandName Invoke-WindowCloseMessage -Times 1 -Exactly
    }
}

Describe 'Windows GUI screenshot already-open-window helper' -Tag 'Unit' -Skip:(-not $script:isSupportedHost) {
    BeforeAll {
        $script:capturePath = Join-Path $PSScriptRoot (
            '..\Skills\windows-gui-screenshot-capture\scripts\WindowCapture.ps1'
        )
        . $script:capturePath
        $script:captureContent = Get-Content -LiteralPath $script:capturePath -Raw -Encoding UTF8

        Add-Type -AssemblyName System.Drawing

        function script:New-TestBitmap {
            param(
                [Parameter(Mandatory, ParameterSetName = 'Solid')]
                [System.Drawing.Color]$Color,

                [Parameter(Mandatory, ParameterSetName = 'Factory')]
                [scriptblock]$PixelFactory
            )

            $bitmap = [System.Drawing.Bitmap]::new(200, 200)

            for ($x = 0; $x -lt $bitmap.Width; $x++) {
                for ($y = 0; $y -lt $bitmap.Height; $y++) {
                    $pixel = if ($PSBoundParameters.ContainsKey('Color')) { $Color } else { & $PixelFactory $x $y }
                    $bitmap.SetPixel($x, $y, $pixel)
                }
            }

            $bitmap
        }
    }

    It 'Should compile its own interop type without colliding with the dialog helper' {
        { Initialize-OpenWindowCapture } | Should -Not -Throw

        'GuiDoc.OpenWindowCapture' -as [type] | Should -Not -BeNullOrEmpty
    }

    It 'Should reject a solid black capture even though PrintWindow would have returned true' {
        $bitmap = script:New-TestBitmap -Color ([System.Drawing.Color]::Black)

        try {
            Test-WindowCaptureContent -Bitmap $bitmap | Should -BeFalse
        }
        finally {
            $bitmap.Dispose()
        }
    }

    It 'Should reject a uniform non-black capture' {
        $bitmap = script:New-TestBitmap -Color ([System.Drawing.Color]::White)

        try {
            Test-WindowCaptureContent -Bitmap $bitmap | Should -BeFalse
        }
        finally {
            $bitmap.Dispose()
        }
    }

    It 'Should accept a painted capture' {
        $bitmap = script:New-TestBitmap -PixelFactory {
            param($x, $y)
            [System.Drawing.Color]::FromArgb(255, ($x % 256), ($y % 256), (($x + $y) % 256))
        }

        try {
            Test-WindowCaptureContent -Bitmap $bitmap | Should -BeTrue
        }
        finally {
            $bitmap.Dispose()
        }
    }

    It 'Should let a raised dark ratio accept a legitimate dark-theme capture' {
        # The skill forbids a universal black threshold: a dark-theme frame must remain acceptable.
        $bitmap = script:New-TestBitmap -PixelFactory {
            param($x, $y)
            if ($y -ge 180) {
                [System.Drawing.Color]::FromArgb(255, ($x % 256), 200, 240)
            }
            else {
                [System.Drawing.Color]::FromArgb(255, ($x % 8), ($y % 3), 0)
            }
        }

        try {
            $strict = @{ Bitmap = $bitmap; MinimumDistinctColor = 5 }
            Test-WindowCaptureContent @strict | Should -BeFalse

            $lenient = @{ Bitmap = $bitmap; MinimumDistinctColor = 5; MaximumDarkRatio = 0.95 }
            Test-WindowCaptureContent @lenient | Should -BeTrue
        }
        finally {
            $bitmap.Dispose()
        }
    }

    It 'Should reject a window handle that is no longer a window' {
        $ownershipParameters = @{
            Process = Get-Process -Id $PID
            Handle  = [System.IntPtr]1
        }

        { Confirm-OpenWindowOwnership @ownershipParameters } |
            Should -Throw -ExpectedMessage '*no longer valid*'
    }

    It 'Should require the owning Process when capturing' {
        $command = Get-Command -Name Save-OpenWindowCapture

        $command.Parameters.ContainsKey('Process') | Should -BeTrue
        $command.Parameters.Process.ParameterType |
            Should -Be ([System.Diagnostics.Process])
    }

    It 'Should verify the handle still belongs to the expected process' {
        $script:captureContent | Should -Match 'GetWindowThreadProcessId'
        $script:captureContent | Should -Match 'if\s*\(\$windowProcessId -ne \$Process\.Id\)'
    }

    It 'Should not discover windows through the foreground window' {
        $script:captureContent | Should -Not -Match 'GetForegroundWindow'
    }

    It 'Should never close or terminate the user-owned target' {
        $script:captureContent | Should -Not -Match 'Stop-Process'
        $script:captureContent | Should -Not -Match 'PostMessage'
        $script:captureContent | Should -Not -Match '\.Kill\(\)'
        $script:captureContent | Should -Not -Match 'CloseMainWindow'
    }

    It 'Should measure the frame with DWMWA_EXTENDED_FRAME_BOUNDS' {
        $script:captureContent | Should -Match 'DwmGetWindowAttribute'
        $script:captureContent | Should -Match 'DWMWA_EXTENDED_FRAME_BOUNDS'
    }

    It 'Should fall back to a composited screen read when the content gate fails' {
        $script:captureContent | Should -Match 'PrintWindow\('
        $script:captureContent | Should -Match 'if\s*\(-not \$printed -or -not \(Test-WindowCaptureContent'
        $script:captureContent | Should -Match 'CopyFromScreen'
    }

    It 'Should re-minimize a window it restored' {
        $script:captureContent | Should -Match '\$wasMinimized = \[GuiDoc\.OpenWindowCapture\]::IsIconic'
        $script:captureContent | Should -Match 'if \(\$wasMinimized -and \[GuiDoc\.OpenWindowCapture\]::IsWindow'
    }
}
