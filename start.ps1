#start.ps1
param(
    $JobFile = $null,
    $ACGCoreDir="$PSScriptroot\Common",
    $LogDir = "C:\CaffeineLogs",
    $LogFile = "$LogDir\CAFination.log",
    [Switch]$SkipVMRearm
)

# =========================================================================== #
# ==================== Start: Bootstrapping the script ====================== #
# =========================================================================== #

$bootstrapLog = "{0}\bootstrap.{1}.{2:yyyyMMddhhmmss}.log" -f $LogDir, $PID, [datetime]::Now
"Starting Caffeination.ps1..." >> $bootstrapLog

"Starting Caffeine bootstrap..." >> $bootstrapLog

"Ensuring elevation..." >> $bootstrapLog
$elevationResult = & "$PSScriptRoot\_ensureElevation.ps1"

if ($elevationResult -ne $true) {
    if ($elevationResult -is [System.Diagnostics.Process]) {
        "We've spawned a process (PID: {0}) to run as Admin, quitting." -f $elevationResult.Id >> $bootstrapLog
    } else {
        "Unable to spawn a new process to run as Admin, Current user ({0}) may not have administrator privileges:" -f (whoami.exe) >> $bootstrapLog
        $elevationResult | Out-String  >> $bootstrapLog
        "Quitting."  >> $bootstrapLog
    }

    return
}

if (-not (Get-Module "ACGCore" -ListAvailable -ea SilentlyContinue)) {
    "ACGCore module not available, copying ACGCore files to PSModulePath..." >> $bootstrapLog
    if (-not (Test-Path $ACGCoreDir)) {
        "Unable to find source directory: '$ACGCoreDir'" >> $bootstrapLog
        "Quitting! @ {0:yyyyMMdd - HH:mm:ss}" -f [datetime]::Now >> $bootstrapLog
    }
    Copy-Item $ACGCoreDir "C:\Windows\System32\WindowsPowerShell\v1.0\Modules\ACGCore" -Recurse *>&1 >> $bootstrapLog
}

"Importing ACGCore..." >> $bootstrapLog
Import-Module ACGCore  *>&1 >> $bootstrapLog
if (-not (Get-Module ACGCore)) {
    "Unable to import ACGCore module from PSModulePath!" >> $bootstrapLog
    "Attempting to import from the given ACGCoreDir..." >> $bootstrapLog
    Import-Module "$ACGCoreDir\ACGCore.psd1"
}

if (-not (Get-Command ShoutOut -ea SilentlyContinue)) {
    "Unable to find the 'shoutOut' command! Quitting!" >> $bootstrapLog
    return
} else {
    "'ShoutOut' is available, starting logging to '$LogFile'..." >> $bootstrapLog
}

"Caffeine bootstrap finished." >> $bootstrapLog

. "$PSScriptRoot\caffeinate.ps1" -JobFile $JobFile -LogFile $LogFile -SkipVMRearm:$SkipVMRearm