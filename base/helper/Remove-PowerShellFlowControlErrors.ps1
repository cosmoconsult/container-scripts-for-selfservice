function Remove-PowerShellFlowControlErrors {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true)]
        [object]$ErrorRecord
    )

    begin {
        $flowControlExceptionType = [System.Management.Automation.PSObject].Assembly.GetType("System.Management.Automation.FlowControlException")
    }

    process {
        if (-not $flowControlExceptionType) {
            $ErrorRecord
            return
        }

        $exception = if ($ErrorRecord -is [System.Management.Automation.ErrorRecord]) {
            $ErrorRecord.Exception
        }
        else {
            $ErrorRecord
        }

        if (-not $flowControlExceptionType.IsInstanceOfType($exception)) {
            $ErrorRecord
        }
    }
}