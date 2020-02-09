#requires -MOdules ACGCore

function _installCAFRegistry {
    param(
        $registryKey,
        $conf,
        $AutorunScript,
        $JobFile,
        $SetupRoot
    )
    $runKey = "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"

    # { reg delete "$registryKey" /f } | Run-Operation #DEBUG
    # { reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v CAFAutorunTrigger /f } | Run-Operation #DEBUG
    # Get-ScheduledTask -TaskName "CAFAutorun" | Unregister-ScheduledTask -Confirm:$false #DEBUG

    shoutOut "`$registryKey='$registryKey'" Cyan

    if ( !(Query-RegValue $registryKey CourseID) ) {
        shoutOut "Initializing CAFSetup Registry key..." Cyan
        $operations = @(
            { reg add "$registryKey" /f }
            { reg add "$registryKey" /v CourseID /t REG_SZ /d "$($conf.Course.Id)" /f }
            { reg add "$registryKey" /v JobName /t REG_SZ /d "$($conf.Job.name)" /f }
            { reg add "$registryKey" /v JobFile /t REG_SZ /d "$JobFile" /f }
            { reg add "$registryKey" /v SetupRoot /t REG_SZ /d "$SetupRoot" /f }
            { reg add "$registryKey" /v CAFDir /t REG_SZ /d "$PSScriptRoot" /f }
            { reg add "$registryKey" /v InstallStep /t REG_DWORD /d 0 /f }
            { reg add "$registryKey" /v NextOperation /t REG_DWORD /d 0 /f }
            { reg add "$registryKey" /v InstallStart /t REG_QWORD /d (Get-Date).Ticks /f }
            { reg query "$registryKey" }
        )
    
        $operations | % { $_ | Run-Operation } | Out-Null
        shoutOut "Done!" Green

<# Caffeine Autorun scheme is deprecated. See install.ps1.
        # The trigger script switches to a Powershell context and executes the Bootstrapper snippet, the bootstrapper
        # snippet then starts a new Powershell context that runs with elevated priviledges and calls the AutorunScript snippet.
        shoutOut "Setting up CAF Autorun..." Cyan
        $CAFAutorunBootstrap =  "echo Bootstrap; echo `$Env:USERNAME; iex ((reg query '$registryKey' /v AutorunScript) | ? { `$_ -match 'REG_[A-Z]+\s+(?<s>.*)$' } | % { `$Matches.s })"
        # $CAFAutorunScript = { echo ('Running CAFAutorun as {0}'-f ${Env:USERNAME}) ; ls C:\CAFAutorun | ? { $_.Name -match '.bat|.ps1' } | % { try{ & $_.FullName *>&1 } catch { Write-host $_ }  } }
        $CAFAutorunScript = $AutorunScript
        $operations = @(
            { reg add "$registryKey" /v AutorunDir /t REG_EXPAND_SZ /d C:\CAFAutorun /f }
            { reg add "$registryKey" /v AutorunBootstrap /t REG_SZ /d "$($CAFAutorunBootstrap.ToString())" /f }
            { reg add "$registryKey" /v AutorunScript /t REG_SZ /d "$($CAFAutorunScript.ToString())" /f }
            # { reg add $runKey /v CAFAutorunTrigger /t REG_SZ /d "Powershell -Command iex (gpv '$registryKey' AutorunBootstrap)" } # Old autorun trigger.
            { reg query "$registryKey" }
            { reg query $runKey }
        )

        # This installation supercedes any previous CAF/CAffeine installation.
        # If the CAFAutorunTrigger value is present under the Run key, that generally means that
        # we are running from a VHD that has already been prepared by Caffeine.
        if (reg query $runkey | select-string CAFAutorunTrigger) {
            $operations += { reg delete $runkey /v CAFAutorunTrigger /f }
        }

        $operations | % { $_ | Run-Operation } | Out-Null
        shoutOut "Done!" Green

        shoutOut "Adding autorun trigger... " Cyan -NoNewline
        
        $jUsername = "$env:COMPUTERNAME\MDTUser"
        $jPassword = 'Pa$$w0rd'

        if (($iCred = $conf.CaffeineCredential) -and ($iCred.Username -and $iCred.Password)) {
            $jPassword = $iCred.Password
            $jUsername = $iCred.Username
            if ($iCred.Domain){
                $jUsername = "{0}\{1}" -f $iCred.Domain,$jUsername
            }
        }

        $jobCredential = New-PSCredential $jUsername $jPassword
        $jobTrigger = New-JobTrigger -AtStartup -RandomDelay (New-Object timespan (0,0,5))
        $jobOptions = New-ScheduledJobOption -RunElevated -ContinueIfGoingOnBattery -MultipleInstancePolicy IgnoreNew
        $jobAction  = {
            param(
                $r
            )
            $dumpFile = "C:\caffeinate.autorun.log"
            "{0:yyyy/MM/dd - HH:mm:ss}" -f (Get-Date) > $dumpFile
            "Using the following key: '{0}'" -f $r >> $dumpFile
            "Key content: " >> $dumpFile
            reg query $r >> $dumpFile
            $bootstrapScript = (reg query $r /v AutorunBootstrap) | Where-Object {
                $_ -match 'REG_[A-Z]+\s+(?<s>.*)$'
            } | ForEach-Object {
                $matches.s
            }

            "Bootstrap script to run:" >> $dumpFile
            $bootstrapScript >> $dumpFile

            $bootstrapScript | % {
                "$_`: ".PadRight(80, "=")
                Invoke-Expression $_ *>> $dumpFile
            }
        }

        $jobParams = @{
            Name = "CAFAutorun"
            Trigger = $jobTrigger
            ScheduledJobOption = $jobOptions
            ScriptBlock = $jobAction
            Credential = $jobCredential
            ArgumentList = $registryKey
        }

        shoutOut "Using the following job parameters: "
        $jobParams | shoutOut 

        $jobDef = { Register-ScheduledJob @jobParams } | Run-Operation
        if ($jobDef -is [System.Management.Automation.ErrorRecord]) {
            "Failed to generate scheduled job! Falling back on the 'Run' key..."
            { reg add HKLM\SOFTWARE\Microsoft\Windows\Currentversion\Run /v CaffeineAutorun /t REG_SZ /d "Powershell -File $PSScriptRoot\caffeinate.ps1" /f } | Run-Operation | Out-Null
        } else {
            shoutOut "Job definition generated:"
            $jobDef | shoutOut
        }

        shoutOut "Caffeine Install Done!" Green
#>
    }
}