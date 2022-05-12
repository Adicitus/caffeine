#requires -Modules ACGCore

function _configureOfflineHKUs {
    param(
        [parameter(Mandatory=$true, Position=1)]$VHDMountDir,
        [parameter(Mandatory=$true, Position=2)]$Configuration
    )

    $rootKey = "HKLM\OFFLINE-HKU"

    $hives = ls "$VHDMountDir\Users\" -Directory | % { "$($_.FullName)\ntuser.dat" } | ? { Test-Path $_ } 

    $hives | % {
        $hive = $_

        shoutOut "Loading offline '$($hive)' hive..."
        $r = {reg load $rootKey "$($hive)"} | Invoke-ShoutOut
        $rf = $r -join "`n"
        if ($rf -match "Error\s?: ") {
            shoutOut "Unable to mount the hive!" Error
            shoutOUt $rf -MsgType Error
            return
        }

        {reg add "$rootKey\Control Panel\International\User Profile" /v InputMethodOverride /t REG_SZ /d "0409:0000041D" /f} | Invoke-ShoutOut -OutNull
        {reg add "$rootKey\Keyboard Layout\Preload" /v 1 /t REG_SZ /d "0000041D" /f} | Invoke-ShoutOut -OutNull

        {reg unload $rootKey } | Invoke-ShoutOut | Out-Null
        
    }
}