function Get-KeybindingKey
{
    <#
        .SYNOPSIS
            Builds the identity tuple of a VS Code keybinding.

        .DESCRIPTION
            Keybindings have no identifier, so the merge treats the combination
            of key, command, and when clause as the identity. Two bindings that
            produce the same tuple are the same binding.

        .PARAMETER Binding
            The parsed keybinding entry.

        .OUTPUTS
            System.String

        .EXAMPLE
            Get-KeybindingKey -Binding $binding

            Returns a comparable identity string such as 'ctrl+k|editor.action|'.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Binding
    )

    $key = if ($Binding.PSObject.Properties['key'])
    {
        [System.String] $Binding.key
    }
    else
    {
        ''
    }

    $command = if ($Binding.PSObject.Properties['command'])
    {
        [System.String] $Binding.command
    }
    else
    {
        ''
    }

    $when = if ($Binding.PSObject.Properties['when'])
    {
        [System.String] $Binding.when
    }
    else
    {
        ''
    }

    return "$key|$command|$when"
}
