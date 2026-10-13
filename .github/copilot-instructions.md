# PowerShell ErrorVariable Handling

After a command uses `-ErrorVariable err`, normalize the captured records before logging them or deriving success from `$err`:

```powershell
$err = @($err | Remove-PowerShellFlowControlErrors)
```

`Remove-PowerShellFlowControlErrors` removes only PowerShell flow-control exceptions, including BC29's `StopUpstreamCommandsException` caused by `Select-Object -First 1` inside the BC management powershell module. Do not discard other error records or use a successful postcondition to ignore unrelated errors.

Dot-source `helper/Remove-PowerShellFlowControlErrors.ps1` before using the function in standalone scripts. `PPIArtifactUtils` loads it automatically.

When reviewing pull requests, flag every PowerShell command that captures `-ErrorVariable` but does not filter the captured value with `Remove-PowerShellFlowControlErrors` before the value is logged or used to determine success.