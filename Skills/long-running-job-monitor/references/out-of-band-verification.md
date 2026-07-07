# Out-of-band target verification

Read-only probes that confirm a long-running job is *genuinely progressing* on the target system, independent of the job's own (often buffered) stdout. Each probe returns a **one-line target-state summary** plus a **change-detector** value the agent compares across samples: if the summary or the change-detector moves between two samples, the job is WORKING; if neither moves past the threshold, it is STALLED. All probes are read-only — never mutate the target while checking on it.

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

Return a `(summary, token)` pair. `token` is any value that strictly advances while the job progresses — a power state, a provisioning phase, a row count, a max id, an uptime, a ready-replica count. The agent stores the previous token and flags STALLED only when the token has not advanced for longer than the threshold.

```powershell
# generic shape a -GetTargetState probe should follow
[pscustomobject]@{ Summary = 'VM 101 running, agent up'; Token = 'running/agent-ok' }
```

## Hypervisor / cloud control plane

Proxmox VE — VM power state across the cluster (change-detector: status):

```powershell
$base = "https://pve:8006/api2/json"
$vms  = (Invoke-RestMethod "$base/cluster/resources?type=vm" -Headers $auth).data
$vm   = $vms | Where-Object vmid -eq 101
"VM {0} {1} (cpu={2:P0} mem={3:N0}MB)" -f $vm.vmid, $vm.status, $vm.cpu, ($vm.mem / 1MB)
```

Azure — VM power/provisioning state (change-detector: PowerState/ProvisioningState):

```powershell
az vm get-instance-view -g $rg -n $vm --query "instanceView.statuses[].code" -o tsv
```

AWS — EC2 instance state (change-detector: State.Name):

```powershell
aws ec2 describe-instances --instance-ids $id --query "Reservations[].Instances[].State.Name" --output text
```

## Guest via QEMU guest-agent

When SSH/WinRM is not up yet (early boot), the hypervisor guest-agent runs a command inside the guest. Proxmox exec (change-detector: service active / hostname reachable):

```powershell
$gpid = (Invoke-RestMethod "$base/nodes/$node/qemu/101/agent/exec" -Method Post -Headers $auth -Body @{ command = 'systemctl is-active nginx' }).data.pid
(Invoke-RestMethod "$base/nodes/$node/qemu/101/agent/exec-status?pid=$gpid" -Headers $auth).data.'out-data'
```

## Guest/host via SSH / WinRM / CIM

> These channels often also *run* the job, not just verify it. To keep the remote job alive when the connection drops and to read its log over the channel, see the "Remote jobs" subsection in [`../SKILL.md`](../SKILL.md).

WinRM (change-detector: service Status / process presence):

```powershell
Invoke-Command -ComputerName $targetHost -Credential $cred -ScriptBlock { (Get-Service MSSQLSERVER).Status }
```

SSH (change-detector: systemctl state):

```powershell
ssh $user@$targetHost 'systemctl is-active nginx && nginx -v 2>&1'
```

Local process (change-detector: process alive):

```powershell
[bool](Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'" | Where-Object CommandLine -match 'job-deploy-vm01')
```

## Database

Change-detector: a monotonic count / max id / status column (a SELECT, never a mutation):

```powershell
Invoke-Sqlcmd -ServerInstance $sql -Query "SELECT COUNT(*) AS n, MAX(id) AS lastId FROM dbo.ImportRows"
```

## HTTP health endpoint

Change-detector: status code / readiness field:

```powershell
try { (Invoke-RestMethod "http://$targetHost/healthz").status } catch { "down: $($_.Exception.Message)" }
```

## Kubernetes

Change-detector: ready replicas / rollout status:

```powershell
kubectl get deploy $name -o jsonpath='{.status.readyReplicas}/{.status.replicas}'
kubectl rollout status deploy/$name --timeout=5s
```
