function Resolve-CopilotAtelierClientVerification
{
    <#
        .SYNOPSIS
            Decides what one client may claim about one artifact from the runtime
            receipts its contract commits.

        .DESCRIPTION
            A runtime receipt records the cases that ran against one exact file:
            the file's SHA-256, the runtime and the version that ran them, the
            date, and the outcome of each case. This function binds a receipt to
            an artifact by that hash and by nothing else.

            While the hash matches, the receipt is bound. The cases it records
            as passed are verified, and when at least one of them ran on the
            runtime, the state is RuntimeVerified at the runtime version the
            receipt names, and VerifiedRuntime names that runtime. A failed
            case is never reported as verified, and a case that only read the
            file never raises the state to a runtime claim; such a File case,
            such as C3, does not depend on a runtime version either.

            Once the hash differs, the receipt is stale. It proves nothing about
            this artifact, so the client contract's own state and version apply
            unchanged and no receipt is returned. An agent without a receipt is
            treated the same way. A client contract that claims RuntimeVerified
            on its own is refused, because only a bound receipt may raise the
            state.

        .PARAMETER ClientContract
            One client entry of Get-CopilotAtelierClientContract, carrying
            VerificationState, VerifiedClientVersion, and RuntimeReceipt.

        .PARAMETER Name
            The Custom agent the artifact belongs to.

        .PARAMETER ArtifactSha256
            The lowercase hexadecimal SHA-256 of the artifact's UTF-8 bytes.

        .OUTPUTS
            System.Management.Automation.PSCustomObject

        .EXAMPLE
            Resolve-CopilotAtelierClientVerification -ClientContract (Get-CopilotAtelierClientContract).Client['copilot-cli'] -Name software-engineer -ArtifactSha256 $hash

            Returns the verification state, the runtime and version it was
            verified on, the verified cases, the receipt, and the receipt status
            for the artifact with that hash.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Object]
        $ClientContract,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Name,

        [Parameter(Mandatory)]
        [ValidatePattern('^[0-9a-f]{64}$', Options = 'None')]
        [System.String]
        $ArtifactSha256
    )

    if ($ClientContract.VerificationState -eq 'RuntimeVerified')
    {
        throw "The client contract claims RuntimeVerified on its own. Only a receipt bound to the SHA-256 of the file its cases ran on may raise the state."
    }

    $receipt = $null
    $receiptMap = $ClientContract.RuntimeReceipt

    if ($receiptMap -and $receiptMap.Contains($Name))
    {
        $receipt = $receiptMap[$Name]
    }

    $status = if (-not $receipt)
    {
        'None'
    }
    elseif ($receipt.ArtifactSha256 -ceq $ArtifactSha256)
    {
        'Bound'
    }
    else
    {
        'Stale'
    }

    if ($status -ne 'Bound')
    {
        return [pscustomobject] @{
            VerificationState     = $ClientContract.VerificationState
            VerifiedRuntime       = $null
            VerifiedClientVersion = $ClientContract.VerifiedClientVersion
            VerifiedCase          = @()
            RuntimeReceipt        = $null
            RuntimeReceiptStatus  = $status
        }
    }

    $passedCase = @($receipt.Case | Where-Object -FilterScript { $_.Outcome -eq 'Passed' })
    $isRuntimeVerified = @($passedCase | Where-Object -FilterScript { $_.Kind -eq 'Runtime' }).Count -gt 0

    return [pscustomobject] @{
        VerificationState     = if ($isRuntimeVerified) { 'RuntimeVerified' } else { $ClientContract.VerificationState }
        VerifiedRuntime       = if ($isRuntimeVerified) { $receipt.RuntimeId } else { $null }
        VerifiedClientVersion = if ($isRuntimeVerified) { $receipt.RuntimeVersion } else { $ClientContract.VerifiedClientVersion }
        VerifiedCase          = @($passedCase | ForEach-Object -Process { $_.Id })
        RuntimeReceipt        = $receipt
        RuntimeReceiptStatus  = $status
    }
}
