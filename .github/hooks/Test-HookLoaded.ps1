[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# Proves only that the workspace hook location loads. Never blocks.
try
{
    $payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
    $event = $payload.hook_event_name
}
catch
{
    $event = 'unreadable'
}

'[{0}] workspace hook loaded, event={1}' -f (Get-Date).ToUniversalTime().ToString('HH:mm:ss'), $event |
    Add-Content -LiteralPath (Join-Path $env:TEMP 'workspace-hook-probe.log')

exit 0
