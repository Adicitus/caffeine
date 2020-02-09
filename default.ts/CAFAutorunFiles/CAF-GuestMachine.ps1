param(
    [Switch]$Silent
)

if (-not (Get-Variable "PSScriptRoot")) {
    $PSScriptRoot = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
}

import-module International

. "$PSScriptRoot\includes\log.ps1"

$logFile = "C:\CAF.log"
$log = {
    param($msg)
    Write-Host $msg
    if ($msg -isnot [String]) {
        $msg = $msg | Out-String
    }
    ("{0}: {1}" -f (Get-Date),$msg) >> $logFile
}

. $log "Running CAF-GuestMachine..."

$sl = Get-WinSystemLocale
if ($sl.Name -ne "en-US") {
    . $log  (Set-WinSystemLocale -SystemLocale "en-US")
}


$hl = Get-WinHomeLocation
if ($hl.GeoId -ne 221) {
    . $log (Set-WinHomeLocation -GeoId 221)
}

$dimo = Get-WinDefaultInputMethodOverride
if (!$dimo -or ($dimo -ne "0409:0000041D")) {
    . $log (Set-WinDefaultInputMethodOverride "0409:0000041D")
}

$rearmPerformed = $false

. $log "computer: $($Env:COMPUTERNAME)"

$licenses = Get-WmiObject SoftwareLicensingProduct | ? {
    $_.LicenseStatus -ne 0 -and $_.LicenseStatus -ne 1
} | ? {
    $_.PartialProductKey
} | ? {
    ($_.LicenseStatus -eq 5) -or ($_.GracePeriodRemaining -lt (1 * 24 * 60))
}# Wait for notification state or until the last 24h to rearm, since we only
 # get ~5 days with some versions of office.

if ($licenses) {
    
    $licenses | % {
            . $log "Rearming: $($_.Description) ($($_.LicenseFamily)): $($_.LicenseStatus) ($($_.GracePeriodRemaining) minutes left, $($_.RemainingSkuReArmCount) SKU rearms left)"
                
            try {
                if ($_ | gm "RearmSku") {

                    if ( ($_.Description -like "*Operating System*") -and !($_.Description -match "Eval") ) {
                        return
                    }

                    . $log ($_.ReArmSku() *>&1)
                    $rearmPerformed = $true
                } else {
                    if ($_.Description -like "Windows Operating System*") {
                        $oslicService = gwmi SoftwareLicensingService
                        . $log ( $oslicService.RearmWindows 2>&1 )
                        $rearmPerformed = $true
                    }
                }
            } catch {
                . $log $_
            }     
        }

} else {
    . $log "No SoftwareLicenses need to be rearmed."
}

if ($onRearmKey = Get-Item HKLM:\SOFTWARE\CAFSetup\Actions\OnRearm -ea SilentlyContinue) {
    $onRearmAction = $onRearmKey.GetValue("action")
} else {
    $onRearmAction = "alwaysShutdown"
}

. $log "OnRearm: $onRearmAction"

if ($rearmPerformed -or ($onRearmAction -match "^always")) {
    Start-Process Powershell -ArgumentList "-Command $PSScriptRoot\includes\RearmRestart.ps1 $onRearmAction" -Wait
} else {
    . $log "No rearm performed and no 'always' action specified."
}

. $log "Finished running CAF-Guestmachine."