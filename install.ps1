#install.ps1

param(
    $SetupFile = "C:\setup\setup.ini",
    $ACGCoreDir,
    [Switch]$StartImmediately
)

$caffeineRoot = "$PSScriptRoot"

$elevationResult = & "$caffeineRoot\_ensureElevation.ps1"

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

$logDir = "C:\CaffeineLogs"
$tmpDir = "C:\temp"

if (-not (Test-Path $logDir -PathType Container)) { mkdir $logDir }
if (-not (Test-Path $tmpDir -PathType Container)) { mkdir $tmpDir }

$installLogFile = "{0}\install.{1}.{2:yyyyMMdd-HHmmss}.log" -f $logDir, $PID, [datetime]::now
"Install started @ {0:yyyy/MM/dd-HH:mm:ss}" -f [datetime]::now >> $installLogFile

# Ensure that ACGCore is available:
if (-not (Get-Module "ACGCore" -ListAvailable -ea SilentlyContinue)) {
    "ACGCore module not available, copying ACGCore files to PSModulePath..." >> $installLogFile
    if (-not (Test-Path $ACGCoreDir)) {
        "Unable to find source directory: '$ACGCoreDir'" >> $installLogFile
        "Quitting install @ {0:yyyyMMdd - HH:mm:ss}" -f [datetime]::Now >> $installLogFile
        return
    }
    Copy-Item $ACGCoreDir "C:\Windows\System32\WindowsPowerShell\v1.0\Modules\ACGCore" -Recurse *>&1 >> $installLogFile
}

Import-Module ACGCore
Set-ShoutOutDefaultLog $installLogFile

& "$PSScriptRoot\_ensureAutoLogon.ps1" $SetupFile $tmpDir $installLogFile

$caffeineTaskName = "Start Caffeine"
if ($oldTask = Get-ScheduledTask $caffeineTaskName) {
    $oldTask | Unregister-ScheduledTask -Confirm:$false
}

"Registering caffeine as a Scheduled Task ('{0}', AtStartup as SYSTEM)..." -f $caffeineTaskName >> $installLogFile
$a = New-ScheduledTaskAction -Execute Powershell.exe -Argument "$caffeineRoot\start.ps1"
$t = New-ScheduledTaskTrigger -AtStartup
$p = New-ScheduledTaskPrincipal -UserId System -LogonType ServiceAccount

$r = Register-ScheduledTask -TaskName $caffeineTaskName -Principal $p -Action $a -Trigger $t

$r | Out-string >> $installLogFile

if ($r -is [Microsoft.Management.Infrastructure.CimInstance]) {
    "Registered caffeine Task successfully." >> $installLogFile
    if ($StartImmediately) {
        "Attempting to start the Task..." >> $installLogFile
        $r | Start-ScheduledTask
        $task = Get-ScheduledTask $caffeineTaskName
        $task | Out-string  >> $installLogFile
    }

    "Installation finished. Quittting @ {0:yyyy/MM/dd - HH:mm:ss}" -f [datetime]::Now >> $installLogFile
} else {
    "Failed to install Caffeine as a task. Quitting @ {0:yyyy/MM/dd - HH:mm:ss}" -f [datetime]::Now >> $installLogFile
}

return