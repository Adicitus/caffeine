
function _installCAFRegistry {
    param(
        $registryKey,
        $JobFile
    )

    $caffeineRoot = $PSScriptRoot

    # { reg delete "$registryKey" /f } | Invoke-ShoutOut #DEBUG
    # { reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v CAFAutorunTrigger /f } | Invoke-ShoutOut #DEBUG
    # Get-ScheduledTask -TaskName "CAFAutorun" | Unregister-ScheduledTask -Confirm:$false #DEBUG

    "`$registryKey='{0}'" -f $registryKey | shoutOut

    if ( !(Query-RegValue $registryKey InstallStart) ) {
        shoutOut "Initializing CAFSetup Registry key..."
        $operations = @(
            { reg add "$registryKey" /f }
            { reg add "$registryKey" /v JobFile /t REG_SZ /d "$JobFile" /f }
            { reg add "$registryKey" /v CAFDir /t REG_SZ /d "$caffeineRoot" /f }
            { reg add "$registryKey" /v InstallStep /t REG_DWORD /d 0 /f }
            { reg add "$registryKey" /v NextOperation /t REG_DWORD /d 0 /f }
            { reg add "$registryKey" /v InstallStart /t REG_QWORD /d (Get-Date).Ticks /f }
            { reg query "$registryKey" }
        )
    
        $operations | ForEach-Object {
            $_ | Invoke-ShoutOut
        } | Out-Null
        shoutOut "Done!" Success

    }
}