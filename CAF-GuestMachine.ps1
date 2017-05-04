param(
    [Switch]$Silent
)

import-module International

$logFile = "C:\CAF.log"

$sl = Get-WinSystemLocale
if ($sl.Name -ne "en-US") {
    Set-WinSystemLocale -SystemLocale "en-US"  *> $logFile
}


$hl = Get-WinHomeLocation
if ($hl.GeoId -ne 221) {
    Set-WinHomeLocation -GeoId 221  *> $logFile
}

$dimo = Get-WinDefaultInputMethodOverride
if (!$dimo -or ($dimo -ne "0409:0000041D")) {
    Set-WinDefaultInputMethodOverride "0409:0000041D"  *> $logFile
}

$Env:COMPUTERNAME
$rearmFiles = ls -Recurse "${env:ProgramFiles(x86)}" -Filter "*ospp.vbs" | % { $_.FullName }
$rearmFiles | write-host $_
$r = $rearmFiles | % { 
    $r = cscript $_ /dstatus
    $rf = $r -join "`n"
    if ($rf -match "REMAINING GRACE: [0-7] days") {
        cscript $_ /dstatus 
    }

} *> $logFile
            
$licenses = Get-WmiObject SoftwareLicensingProduct | ? {
    $_.LicenseStatus -ne 1
} | ? {
    $_.PartialProductKey -and ($_.Licensefamily -match "Office|Eval") -and ( ($_.LicenseStatus -eq 5) -or ( ($_.GracePeriodRemaining -lt (1 * 24 * 60))) )
} # wait until the last 24h to rearm, since we only get ~5 days with some versions of office.,

if ($licenses) {
    
    $licenses | % {
        "$($_.Description) ($($_.LicenseFamily)): $($_.LicenseStatus) ($($_.GracePeriodRemaining) minutes left, $($_.RemainingSkuReArmCount) SKU rearms left)" >> "$PSScriptRoot\Autorun.log"
                
        try {
            if ($_.Licensefamily -match "Office|Eval") {
                $_.ReArmSku() *> $logFile
            }
            sleep 10
        } catch {
            $_  *> $logFile
        }     
    }

    # Prompt for consent to restart the machine.
    # [MessageBox] is not an option since availability is spotty.

    if(!$Silent) {
        $restartQuery = ( {
            Write-Host 'Some of the licenses on this machine were about to expire and have been reactivated.'
            Write-Host 'The machine needs to be restarted in order for these changes to finish.'
            $r = ""
            while ($r -notmatch '^y|yes|yeah|yep|n|no|nope|nah$') {
                $r = Read-Host -Prompt 'Would you like to restart now? (Y/N)'
                if ($r -match '^y|yes|yeah|yep$' ) {
                    shutdown /r /t 5
                }
            }
        }.ToString() )

        start powershell ('-Command {0}' -f $restartQuery)

    }
}