
function _ensureElevation {
    param(
        $Command
    )

    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal $currentIdentity

    $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (!$isAdmin) {
        $elevationArgs = @{
            Verb="RunAs"
        }

        "Attempting to start an elevated shell with the following command: {0}" -f $Command | ShoutOut
        $elevationArgs.ArgumentList = "-Command {0}" -f $Command

        try {
            $proc = Start-Process Powershell @elevationArgs -PassThru
            "Started a new Powershell session as Admin" | shoutOut 
            return $proc
        } catch {
            "Unable to start new Powershell Admin session:" | shoutOut
            $_ | shoutOut
            return $_
        }

        $errMsg = "Unexpected state in '{0}'. Should have returned [Process], [ErrorRecord] or `$True. Something is very wrong." -f "$PSScriptRoot\_ensureElevation.ps1"
        throw $errMsg
    }

    return $true
}