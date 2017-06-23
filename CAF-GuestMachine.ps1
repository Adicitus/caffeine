param(
    [Switch]$Silent
)

import-module International

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
$rearmFiles = ls -Recurse "${env:ProgramFiles(x86)}" -Filter "*ospp.vbs" | % { $_.FullName }
. $log  ("Office Rearm files (*ospp.vbs) found: $( $rearmFiles -join ", " )")
$r = $rearmFiles | % {
    . $log "Checking $_"
    $r = cscript $_ /dstatus
    $rf = $r -join "`n"
    if ($rf -match "REMAINING GRACE: [0-7] days") {
        . $log (cscript $_ /rearm *>&1)
        $rearmPerformed = $true
        . $log "Rearmed."
    } else {
        . $log "No need to rearm."
    }

} *>&1

. $log $r

$licenses = Get-WmiObject SoftwareLicensingProduct | ? {
    $_.LicenseStatus -ne 1
} | ? {
    $_.PartialProductKey -and ($_.Licensefamily -match "Office|Eval")
} | ? {
    ($_.LicenseStatus -eq 5) -or ($_.GracePeriodRemaining -lt (1 * 24 * 60))
}# Wait for notification state or until the last 24h to rearm, since we only
 # get ~5 days with some versions of office.

if ($licenses) {
    
    $licenses | % {
            . $log "Rearming: $($_.Description) ($($_.LicenseFamily)): $($_.LicenseStatus) ($($_.GracePeriodRemaining) minutes left, $($_.RemainingSkuReArmCount) SKU rearms left)"
                
            try {
                if ($_.Licensefamily -match "Office|Eval") {
                    $_.ReArmSku() *>&1
                    $rearmPerformed = $true
                }
                sleep 10
            } catch {
                . $log $_
            }     
        }

} else {
    . $log "No SoftwareLicenses need to be rearmed."
}

# Prompt for consent to restart the machine.
# [MessageBox] is not an option since availability is spotty.

$prompt = {
    param ($action, $switch)
    $restartQuery = {
        Write-Host "Some of the licenses on this machine were about to expire and have been reactivated."
        Write-Host "The machine needs to be $action in order for these changes to finish."
        $r = ""
        while ($r -notmatch '^y|yes|yeah|yep|n|no|nope|nah$') {
            $r = Read-Host -Prompt 'Would you like to restart now? (Y/N)'
            if ($r -match '^y|yes|yeah|yep$' ) {
                shutdown $switch /t 5
            }
        }
    }

    . $restartQuery

}


if ($onRearmKey = Get-Item HKLM:\SOFTWARE\CAFSetup\Actions\OnRearm -ea SilentlyContinue) {
    $onRearmAction = $onRearmKey.GetValue("action")
} else {
    $onRearmAction = "alwaysShutdown"
}

. $log "OnRearm: $onRearmAction"

if ($rearmPerformed -or ($onRearmAction -match "^always")) {
    switch -Regex ($onRearmAction) {
        "promptShutdown" {
            . $log "OnRearm action: prompt for shutdown"
            . $prompt "Shut down" "/s"
        }
        "promptRestart" {
            . $log "OnRearm action: prompt for restart"
            . $prompt "restart" "/r"
        }
        "Shutdown" {
            . $log "OnRearm action: shutdown"
            shutdown /s /t 0
        }
        "Restart" {
            . $log "OnRearm action: Restart"
            shutdown /r /t 0
        }
        default {
            . $log "Default OnRearm action: shutdown"
            Shutdown /s /t 0
        }
    }
} else {
    . $log "No rearm performed and no 'always' action specified."
}

. $log "Finished running CAF-Guestmachine."