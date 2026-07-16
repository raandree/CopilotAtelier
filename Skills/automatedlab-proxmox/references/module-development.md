# Module development and reload safety

Use this workflow when source is patched locally and the installed
AutomatedLab module must be exercised by a live deployment.

## Detect stale in-memory dependencies

`Import-Module AutomatedLab -Force` does not guarantee that already-loaded
`AutomatedLabCore` or `AutomatedLabWorker` dependencies are replaced. A shell
started before installation can continue running obsolete private functions.

Check all three forms of evidence:

- `Get-Module` path and version.
- `Get-Command` source and definition from the owning module scope.
- Required behavior or capability, such as a `Wait` parameter or command order.

Remove dependents before dependencies, then import from disk again. Verify the
new capabilities before defining or changing a lab.

## Capability guards

A guard must test the behavior needed by the deployment, not a nearby edit.

Examples:

- For restart ordering, verify `Wait-LabVM` occurs before
  `Repair-LWProxmoxNetworkConfig`, not only that a later flag assignment uses
  `-bor`.
- For waited QEMU execution, verify the command exposes `-Wait` and that the
  expected Sysprep helper exists.

Private commands may require invocation in module scope:

```powershell
$worker = Get-Module -Name AutomatedLabWorker -ErrorAction Stop
$hasWait = & $worker {
    (Get-Command Start-LWProxmoxAgentExecutionOnVM).Parameters.ContainsKey('Wait')
}
```

String-definition checks are useful as temporary development guards but are
format-sensitive. Prefer tests or an explicit versioned capability when a
stable public contract becomes available.

## External script scope and task waits

`Wait-LWProxmoxTasksStatus` is an internal, non-exported
AutomatedLabWorker function. An external template-probe or maintenance script
cannot call it as though it were a public command.

When clone, stop, or remove operations run outside module scope, poll the public
`Get-LWProxmoxVM ... -NoCache` result for the required VM postcondition. Keep an
explicit timeout and surface the last observed status. Do not copy the private
wait helper into the script or depend on module-scope invocation for production
automation.

Module-scope invocation remains appropriate for capability inspection of
private functions during development; it does not make those functions part of
the external scripting contract.

## Build without the full toolchain

When `dotnet` or repository `requiredmodules` are unavailable, do not invent a
module layout. Read the repository build task and reproduce only its module
assembly algorithm.

In the investigated AutomatedLab version, the module concatenation order was:

1. `internal/functions`
2. `functions`
3. `internal/scripts`

Treat that order as version-specific and re-read the build task on every new
version.

## Artifact validation

Before replacing an installed module:

1. Build into a unique directory under `$env:TEMP`.
2. Parse the generated `.psm1` with the PowerShell parser.
3. Copy unchanged runtime dependencies into the temporary layout.
4. Import the artifact in a fresh isolated PowerShell process.
5. Resolve the changed commands and verify required capabilities.
6. Back up the installed artifact.
7. Replace it and compare SHA-256 hashes.
8. Start another fresh process and verify the installed module from disk.

After live validation, rebuild from current source and require its hash to
match the installed module that passed. This closes the gap between source,
temporary artifact, installed file, and in-memory command.

## Test layers

Use the cheapest discriminating check first:

- Focused Pester test for ordering or result semantics.
- PowerShell parser for changed source and generated artifacts.
- ScriptAnalyzer relative to the repository baseline.
- Isolated import and capability probe.
- Controlled single-guest live test.
- Full deployment only after the focused live test passes.

Keep source, test, changelog, and deployment-harness changes in separate
logical commits when they live in different repositories.

## Common failure modes

- Importing a temporary `.psm1` without its required `lib` directory.
- Comparing source with an installed file while the shell still uses old code.
- Guarding a proxy edit instead of the actual behavior.
- Calling internal `Wait-LWProxmoxTasksStatus` from external script scope.
- Replacing the installed module without a rollback copy and hash.
- Running a full destructive deployment before a focused restart test.
