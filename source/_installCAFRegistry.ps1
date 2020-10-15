
function _installCAFRegistry {
    param(
        $registryKey,
        $conf,
        $AutorunScript,
        $JobFile,
        $SetupRoot
    )

    $caffeineRoot = $PSScriptRoot

    # { reg delete "$registryKey" /f } | Run-Operation #DEBUG
    # { reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v CAFAutorunTrigger /f } | Run-Operation #DEBUG
    # Get-ScheduledTask -TaskName "CAFAutorun" | Unregister-ScheduledTask -Confirm:$false #DEBUG

    "`$registryKey='{0}'" -f $registryKey | shoutOut

    if ( !(Query-RegValue $registryKey CourseID) ) {
        shoutOut "Initializing CAFSetup Registry key..."
        $operations = @(
            { reg add "$registryKey" /f }
            { reg add "$registryKey" /v CourseID /t REG_SZ /d "$($conf.Course.Id)" /f }
            { reg add "$registryKey" /v JobName /t REG_SZ /d "$($conf.Job.name)" /f }
            { reg add "$registryKey" /v JobFile /t REG_SZ /d "$JobFile" /f }
            { reg add "$registryKey" /v SetupRoot /t REG_SZ /d "$SetupRoot" /f }
            { reg add "$registryKey" /v CAFDir /t REG_SZ /d "$caffeineRoot" /f }
            { reg add "$registryKey" /v InstallStep /t REG_DWORD /d 0 /f }
            { reg add "$registryKey" /v NextOperation /t REG_DWORD /d 0 /f }
            { reg add "$registryKey" /v InstallStart /t REG_QWORD /d (Get-Date).Ticks /f }
            { reg query "$registryKey" }
        )
    
        $operations | ForEach-Object {
            $_ | Run-Operation
        } | Out-Null
        shoutOut "Done!" Success

    }
}