
function _ensureElevation {
    param(
        $logFile
    )

    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal $currentIdentity

    $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    $callStack = Get-PSCallStack

    $caller = $callStack[1]

    if (!$isAdmin) {
        $args = @{
            Verb="RunAs"
        }

        if ($caller.ScriptName) {
            $args.ArgumentList = "-Command {0}; {1}" -f $caller.ScriptName, "Pause"
        }

        try {
            $proc = Start-Process Powershell @args -PassThru
            if ($logFile) { "Started a new Powershell session as Admin" >> $logFile }
            return $proc
        } catch {
            if ($logFile) { "Unable to start new Powershell Admin session:" >> $logFile }
            if ($logFile) { $_ | Out-string >> $logFile }
            return $_
        }

        $errMsg = "Unexpected state in '{0}'. Should have returned [Process], [ErrorRecord] or `$True. Something is very wrong." -f "$PSScriptRoot\_ensureElevation.ps1"
        throw $errMsg
    }

    return $true
}