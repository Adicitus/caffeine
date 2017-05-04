﻿. "$PSScriptRoot\Common\Query-RegValue.ps1"

function Install-CAFRegistry {
    param($registryKey, $conf, $AutorunScript)
    $runKey = "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"

    # { reg delete "$registryKey" /f } | Run-Operation #DEBUG
    # { reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v CAFAutorunTrigger /f } | Run-Operation #DEBUG
    # Get-ScheduledTask -TaskName "CAFAutorun" | Unregister-ScheduledTask -Confirm:$false #DEBUG

    shoutOut "`$registryKey='$registryKey'" Cyan

    if ( !(Query-RegValue $registryKey CourseID) ) {
        shoutOut "Initializing CAFSetup Registry key..." Cyan
        $operations = @(
            { reg add "$registryKey" }
            { reg add "$registryKey" /v CourseID /t REG_SZ /d "$($conf.Course.Id)" }
            { reg add "$registryKey" /v JobName /t REG_SZ /d "$($conf.Job.name)" }
            { reg add "$registryKey" /v JobFile /t REG_SZ /d "$JobFile" }
            { reg add "$registryKey" /v SetupRoot /t REG_SZ /d "$SetupRoot" }
            { reg add "$registryKey" /v InstallStep /t REG_DWORD /d 0 }
            { reg add "$registryKey" /v NextOperation /t REG_DWORD /d 0 }
            { reg add "$registryKey" /v InstallStart /t REG_QWORD /d (Get-Date).Ticks }
            { reg query "$registryKey" }
        )
    
        $operations | % { $_ | Run-Operation } | Out-Null
        shoutOut "Done!" Green
    
        # The trigger script switches to a Powershell context and executes the Bootstrapper snippet, the bootstrapper
        # snippet then starts a new Powershell context that runs with elevated privilidges and calls the AutorunScript snippet.
        shoutOut "Setting up CAF Autorun..." Cyan
        $CAFAutorunBootstrap =  "echo Bootstrap; echo `$Env:USERNAME; iex ((reg query '$registryKey' /v AutorunScript) | ? { `$_ -match 'REG_[A-Z]+\s+(?<s>.*)$' } | % { `$Matches.s })"
        # $CAFAutorunScript = { echo ('Running CAFAutorun as {0}'-f ${Env:USERNAME}) ; ls C:\CAFAutorun | ? { $_.Name -match '.bat|.ps1' } | % { try{ & $_.FullName *>&1 } catch { Write-host $_ }  } }
        $CAFAutorunScript = $AutorunScript
        $operations = @(
            { reg add "$registryKey" /v AutorunDir /t REG_EXPAND_SZ /d C:\CAFAutorun }
            { reg add "$registryKey" /v AutorunBootstrap /t REG_SZ /d "$($CAFAutorunBootstrap.ToString())"}
            { reg add "$registryKey" /v AutorunScript /t REG_SZ /d "$($CAFAutorunScript.ToString())"}
            # { reg add $runKey /v CAFAutorunTrigger /t REG_SZ /d "Powershell -Command iex (gpv '$registryKey' AutorunBootstrap)" } # Old autorun trigger.
            { reg query "$registryKey" }
            { reg query $runKey }
        )

        $operations | % { $_ | Run-Operation } | Out-Null
        shoutOut "Done!" Green

        shoutOut "Adding autorun trigger... " Cyan -NoNewline

        $ta = New-ScheduledTaskAction -Execute "cmd" -Argument "/C start `"CAF Autorun`" /MAX Powershell `"Get-Date > C:\autorundump; (reg query '$registryKey' /v AutorunBootstrap) | ? { `$_ -match 'REG_[A-Z]+\s+(?<s>.*)$' } | % { iex `$matches.s *>> C:\autorundump }`""
        $tt = New-ScheduledTaskTrigger -AtStartup
        $t = New-ScheduledTask -Action $ta -Trigger $tt -Settings (New-ScheduledTaskSettingsSet)
        $r = $t | Register-ScheduledTask -User "Administrator" -Password 'Pa$$w0rd' -TaskName "CAFAutorun"
        shoutOut "Done! ($($r.State))" Green
    }
}