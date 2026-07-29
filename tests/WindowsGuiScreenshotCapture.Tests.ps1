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
