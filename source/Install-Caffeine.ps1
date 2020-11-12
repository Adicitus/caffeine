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

    $elevationResult = _ensureElevation

    if ($elevationResult -ne $true) {
        if ($elevationResult -is [System.Diagnostics.Process]) {
            "We've spawned a process (PID: {0}) to run as Admin, quitting." -f $elevationResult.Id | Write-Host -ForegroundColor Green
        } else {
            "Unable to spawn a new process to run as Admin, Current user ({0}) may not have administrator privileges:" -f (whoami.exe) | Write-Host -ForegroundColor Red
            $elevationResult | Out-String | Write-Host -ForegroundColor Red
            "Quitting." | Write-Host -ForegroundColor Red
        }

        return
    }

    # At this point we should be running as admin

    $tmpDir = "C:\temp"

    if (-not (Test-Path $logDir -PathType Container)) { mkdir $logDir }
    if (-not (Test-Path $tmpDir -PathType Container)) { mkdir $tmpDir }

    $installLogFile = "{0}\install.{1:yyyyMMdd-HHmmss}.{2}.log" -f $logDir, [datetime]::now, $PID
    "Install started @ {0:yyyy/MM/dd-HH:mm:ss}" -f [datetime]::now >> $installLogFile

    $setup = Parse-ConfigFile $SetupFile

    _ensureAutoLogon $Setup $tmpDir $installLogFile

    $caffeineTaskName = "Start Caffeine"
    if ($oldTask = Get-ScheduledTask $caffeineTaskName) {
        $oldTask | Unregister-ScheduledTask -Confirm:$false
    }

    "Registering caffeine as a Scheduled Task ('{0}', AtStartup as SYSTEM)..." -f $caffeineTaskName >> $installLogFile
    $a = New-ScheduledTaskAction -Execute Powershell.exe -Argument "Start-Caffeine -JobFile '$SetupFile'"
    $t = New-ScheduledTaskTrigger -AtStartup
    $s = New-ScheduledTaskSettingsSet -Priority 3 -AllowStartIfOnBatteries
    $p = New-ScheduledTaskPrincipal -UserId System -LogonType ServiceAccount

    $r = Register-ScheduledTask -TaskName $caffeineTaskName -Principal $p -Action $a -Trigger $t -Settings $s

    $r | Out-string >> $installLogFile

    if ($r -is [Microsoft.Management.Infrastructure.CimInstance]) {
        "Registered caffeine Task successfully." >> $installLogFile
        if ($StartImmediately) {
            "Attempting to start the Task..." >> $installLogFile
            $r | Start-ScheduledTask
            $task = Get-ScheduledTask $caffeineTaskName
            $task | Out-string  >> $installLogFile
        }

        "Installation finished. Quitting @ {0:yyyy/MM/dd - HH:mm:ss}" -f [datetime]::Now >> $installLogFile
    } else {
        "Failed to install Caffeine as a task. Quiting @ {0:yyyy/MM/dd - HH:mm:ss}" -f [datetime]::Now >> $installLogFile
    }

}