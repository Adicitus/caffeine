<#
.SYNOPSIS
Installs Caffeine as a Scheduled Task to be run @ startup as SYSTEM.

.PARAMETER SetupFile
Setup .ini file with instructions on how to do the installation.

Currently only accepts a section called "Credential-AutoLogon" with the following fields:
    + Username: name oi the user to autologon as.
    + Domain: domain that the user belongs to ('.' for local accounts).
    + Password: clear-text password for the user.

All 3 fields are currently mandatory.

.PARAMETER LogDir
Path to the folder where log file should be written.

.PARAMETER StartImmediately
Switch to determine if the Scheduled Task should be run immediately after install completes.

#>
function Install-Caffeine {
    param(
        $SetupFile = "C:\setup\setup.ini",
        $LogDir = "C:\CaffeineLogs",
        [Switch]$StartImmediately
    )

    $installLogFile = "{0}\install.{1:yyyyMMdd-HHmmss}.{2}.log" -f $logDir, [datetime]::now, $PID

    Set-ShoutOutDefaultLog -LogFilePath $installLogFile

    "Install started @ {0:yyyy/MM/dd-HH:mm:ss}" -f [datetime]::now | shoutOut

    $cmd = 'Install-Caffeine -SetupFile {0} -LogDir {1}' -f $SetupFile, $LogDir
    if ($StartImmediately) {
        $cmd += " -StartImmediately"
    }
    $elevationResult = _ensureElevation $cmd

    if ($elevationResult -ne $true) {
        if ($elevationResult -is [System.Diagnostics.Process]) {
            "We've spawned a process (PID: {0}) to run as Admin, quitting." -f $elevationResult.Id | ShoutOut -MsgType Success
        } else {
            "Unable to spawn a new process to run as Admin, Current user ({0}) may not have administrator privileges:" -f (whoami.exe) | ShoutOut -MsgType Error
            $elevationResult | Out-String | shoutOut
            "Quitting." | ShoutOut
        }

        return
    }

    # At this point we should be running as admin

    $tmpDir = "C:\temp"

    if (-not (Test-Path $tmpDir -PathType Container)) { mkdir $tmpDir }

    $setup = Parse-ConfigFile $SetupFile

    _ensureAutoLogon $Setup $tmpDir

    $caffeineTaskName = "Start Caffeine"
    if ($oldTask = Get-ScheduledTask $caffeineTaskName) {
        $oldTask | Unregister-ScheduledTask -Confirm:$false
    }

    "Registering caffeine as a Scheduled Task ('{0}', AtStartup as SYSTEM)..." -f $caffeineTaskName | shoutOut
    $a = New-ScheduledTaskAction -Execute Powershell.exe -Argument "Start-Caffeine -JobFile '$SetupFile'"
    $t = New-ScheduledTaskTrigger -AtStartup
    $s = New-ScheduledTaskSettingsSet -Priority 3 -AllowStartIfOnBatteries
    $p = New-ScheduledTaskPrincipal -UserId System -LogonType ServiceAccount

    $r = Register-ScheduledTask -TaskName $caffeineTaskName -Principal $p -Action $a -Trigger $t -Settings $s

    $r | Out-string | shoutOut

    if ($r -is [Microsoft.Management.Infrastructure.CimInstance]) {
        "Registered caffeine Task successfully." | shoutOut
        if ($StartImmediately) {
            "Attempting to start the Task..." | shoutOut
            $r | Start-ScheduledTask
            $task = Get-ScheduledTask $caffeineTaskName
            $task | Out-string  | shoutOut
        }

        "Installation finished. Quitting @ {0:yyyy/MM/dd - HH:mm:ss}" -f [datetime]::Now | shoutOut
    } else {
        "Failed to install Caffeine as a task. Quiting @ {0:yyyy/MM/dd - HH:mm:ss}" -f [datetime]::Now | shoutOut
    }

}