# Out-of-band target verification

Read-only probes that distinguish genuine target progress from controller or
target liveness when a job's stdout is buffered. Each probe returns a summary,
a liveness signal, and a phase-specific progress token. Only progress-token
advancement resets the stall clock. A changing summary, fresh heartbeat,
uptime, CPU, memory, or process existence proves liveness or activity, not
progress. All probes are read-only.

## Contents

- [Out-of-band target verification](#out-of-band-target-verification)
  - [Contents](#contents)
  - [Change-detector pattern](#change-detector-pattern)
  - [Hypervisor / cloud control plane](#hypervisor--cloud-control-plane)
  - [Guest via QEMU guest-agent](#guest-via-qemu-guest-agent)
  - [Guest/host via SSH / WinRM / CIM](#guesthost-via-ssh--winrm--cim)
  - [Database](#database)
  - [HTTP health endpoint](#http-health-endpoint)
  - [Kubernetes](#kubernetes)

## Change-detector pattern

Return `Summary`, `Liveness`, and `ProgressToken` separately.

- `Summary` is human-readable and may contain volatile telemetry. Never compare
  it to classify progress.
- `Liveness` records whether the target or observer responds. It does not reset
  the stall clock.
- `ProgressToken` is a phase milestone or monotonic work product that can
  advance toward the expected postcondition: provisioning phase, completed-row
  count, maximum imported ID, ready-replica count, or a one-time transition to
  the required service state.

Store the prior progress token and its timestamp. Classify `STALLED` when that
token remains unchanged beyond the phase threshold, even if liveness and
volatile telemetry continue changing. Power state is a progress token only
when the current phase expects a specific transition; repeated `running` is
static. Uptime is never a progress token.

```powershell
# Generic shape a -GetTargetState probe should follow.
[pscustomobject]@{
  Summary       = 'VM 101 running, agent up'
  Liveness      = $true
  ProgressToken = 'guest-agent-ready'
}
```

## Hypervisor / cloud control plane

Proxmox VE: report power state, but use only an expected state transition as a
progress token. Exclude CPU, memory, and uptime.

```powershell
$base = "https://pve:8006/api2/json"
$vms  = (Invoke-RestMethod "$base/cluster/resources?type=vm" -Headers $auth).data
$vm   = $vms | Where-Object vmid -eq 101
[pscustomobject]@{
  Summary       = "VM $($vm.vmid) $($vm.status)"
  Liveness      = $null -ne $vm
  ProgressToken = if ($vm.status -eq $expectedVmState) { $vm.status } else { $null }
}
```

Azure: use provisioning-state transitions for provisioning work. A static power
state is liveness/context after its expected transition, not continuing
progress.

```powershell
az vm get-instance-view -g $rg -n $vm --query "instanceView.statuses[].code" -o tsv
```

AWS: use instance-state changes only when the phase expects that transition.

```powershell
aws ec2 describe-instances --instance-ids $id --query "Reservations[].Instances[].State.Name" --output text
```

## Guest via QEMU guest-agent

When SSH/WinRM is not up yet, the hypervisor guest agent can verify a required
service transition. Repeated `active` is a reached milestone, not repeated
progress.

```powershell
$gpid = (Invoke-RestMethod "$base/nodes/$node/qemu/101/agent/exec" -Method Post -Headers $auth -Body @{ command = 'systemctl is-active nginx' }).data.pid
(Invoke-RestMethod "$base/nodes/$node/qemu/101/agent/exec-status?pid=$gpid" -Headers $auth).data.'out-data'
```

## Guest/host via SSH / WinRM / CIM

> These channels often also *run* the job, not just verify it. To keep the remote job alive when the connection drops and to read its log over the channel, see the "Remote jobs" subsection in [`../SKILL.md`](../SKILL.md).

WinRM: service-state transition can satisfy a milestone. Repeated status is
static.

```powershell
Invoke-Command -ComputerName $targetHost -Credential $cred -ScriptBlock { (Get-Service MSSQLSERVER).Status }
```

SSH: service-state transition can satisfy a milestone. Repeated status is
static.

```powershell
ssh $user@$targetHost 'systemctl is-active nginx && nginx -v 2>&1'
```

Local process existence is liveness only. Pair it with a real progress token
such as a completed-item count or phase marker.

```powershell
[pscustomobject]@{
  Summary       = 'Deployment process probe'
  Liveness      = [bool](Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'" |
    Where-Object CommandLine -match 'job-deploy-vm01')
  ProgressToken = $null
}
```

## Database

Use a monotonic count, maximum ID, or ordered status milestone tied to the job's
own output rows. A SELECT never mutates the target.

```powershell
Invoke-Sqlcmd -ServerInstance $sql -Query "SELECT COUNT(*) AS n, MAX(id) AS lastId FROM dbo.ImportRows"
```

## HTTP health endpoint

Use a readiness-field transition as a milestone. Repeated HTTP 200 is static
after readiness is reached.

```powershell
try { (Invoke-RestMethod "http://$targetHost/healthz").status } catch { "down: $($_.Exception.Message)" }
```

## Kubernetes

Use ready-replica or rollout-generation advancement toward the desired state.

```powershell
kubectl get deploy $name -o jsonpath='{.status.readyReplicas}/{.status.replicas}'
kubectl rollout status deploy/$name --timeout=5s
```
