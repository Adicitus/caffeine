. "$PSScriptRoot\Common\ShoutOut.ps1"
. "$PSScriptRoot\Common\Run-Operation.ps1"

function Configure-OfflineHKUs {
    param(
        [parameter(Mandatory=$true, Position=1)]$VHDMountDir,
        [parameter(Mandatory=$true, Position=2)]$Configuration
    )

    $rootKey = "HKLM\OFFLINE-HKU"

    $hives = ls "$VHDMountDir\Users\" -Directory | % { "$($_.FullName)\ntuser.dat" } | ? { Test-Path $_ } 

    $hives | % {
        $hive = $_

        shoutOut "Loading offline '$($hive)' hive..." Cyan
        $r = {reg load $rootKey "$($hive)"} | Run-Operation
        $rf = $r -join "`n"
        if ($rf -match "Error\s?: ") {
            shoutOut "Unable to mount the hive!" Red
            return
        }

        {reg add "$rootKey\Control Panel\International\User Profile" /v InputMethodOverride /t REG_SZ /d "0409:0000041D" /f} | Run-Operation -OutNull
        {reg add "$rootKey\Keyboard Layout\Preload" /v 1 /t REG_SZ /d "0000041D" /f} | Run-Operation -OutNull

        {reg unload $rootKey } | Run-Operation | Out-Null
        
    }
}