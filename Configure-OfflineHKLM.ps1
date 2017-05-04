. "$PSScriptRoot\Common\ShoutOut.ps1"
. "$PSScriptRoot\Common\Run-Operation.ps1"
. "$PSScriptRoot\Common\Steal-RegKey.ps1"

function Configure-OfflineHKLM {
    param(
        [parameter(Mandatory=$true, Position=1)]$VHDMountDir,
        [parameter(Mandatory=$true, Position=2)]$Configuration
    )
    $rootKey = "HKLM\OFFLINE-SOFTWARE"
    shoutOut "Loading offline SOFTWARE hive..." Cyan
    {reg load $rootKey "$VHDMountDir\Windows\System32\config\SOFTWARE"} | Run-Operation | Out-Null
    $r = {reg query "$rootKey\"} | Run-Operation
    if (($r | ? { $_ -match "CAFSetup$" })) { "reg delete $rootKey\CAFSetup /f" | Run-Operation | Out-Null; $r = "reg query `"$rootKey\`"" | Run-Operation | Out-Null } #DEBUG
        
        
    if ( !($r | ? { $_ -match "CAFSetup$" }) ) {
            
        shoutOut "Setting up local CAF..." Cyan
        $CAFAutorunBootstrap =  { start Powershell -Verb RunAs -ArgumentList '-WindowStyle Hidden -ExecutionPolicy Bypass -NoProfile -Command echo Bootstrap; echo $Env:USERNAME; iex (gpv HKLM:\SOFTWARE\CAFSetup AutorunScript)' }
        $CAFAutorunScript = { echo ('Running CAFAutorun as {0}'-f ${Env:USERNAME}) ; ls C:\CAFAutorun | ? { $_.Name -match '.bat|.ps1' } | % { try{ & $_.FullName *>&1 } catch { Write-host $_ }  } }
            
        $operations = @(
            { reg add "$rootKey\CAFSetup"},
            { reg add $rootKey\CAFSetup /v AutorunDir /t REG_EXPAND_SZ /d C:\CAFAutorun },
            { reg add $rootKey\CAFSetup /v AutorunCount /t REG_DWORD /d 0 },
            { reg add $rootKey\CAFSetup /v AutorunBootstrap /t REG_SZ /d "$($CAFAutorunBootstrap.ToString())"},
            { reg add $rootKey\CAFSetup /v AutorunScript /t REG_SZ /d "$($CAFAutorunScript.ToString())"},
            { reg query $rootKey\CAFSetup }
        )

        $operations | % { Run-Operation $_ }  | Out-Null

        shoutOut "Done!" Green
    }

    if ( { reg query "$rootKey\Microsoft\Windows\CurrentVersion\Run" | ? { $_ -match "^\s*CAFAutorunTrigger" } } | Run-Operation |Out-Null) { shoutOut "Deleting old Trigger..." Cyan; { reg delete "$rootKey\Microsoft\Windows\CurrentVersion\Run" /v CAFAutorunTrigger /f } | Run-Operation | Out-Null } #DEBUG

    # The trigger script switches to a Powershell context and executes the Bootstrapper snippet, the bootstrapper
    # snippet then starts a new Powershell context that runs with elevated privilidges and calls the AutorunScript snippet.
    $r = { reg query "$rootKey\Microsoft\Windows\CurrentVersion\Run" } | Run-Operation
    if ( !($r | ? { $_ -match "^\s*CAFAutorunTrigger" }) ) {
        shoutOut "Adding CAF autorun trigger..." Cyan
        $r = { reg add "$rootKey\Microsoft\Windows\CurrentVersion\Run" /v CAFAutorunTrigger /t REG_SZ /d "Powershell -Command iex (gpv HKLM:\SOFTWARE\CAFSetup AutorunBootstrap)" } | Run-Operation
        $r | % { shoutOut "`t| $_" White }
    }


    shoutOut "Making Quality of Life changes to hive..." Cyan

    $operations = @(
        # Prevent UAC consent prompts for admins, as described @ http://www.ghacks.net/2013/06/20/how-to-configure-windows-uac-prompt-behavior-for-admins-and-users/
        "reg add $rootKey\Microsoft\Windows\CurrentVersion\Policies\System /v ConsentPromptBehaviorAdmin /t REG_DWORD /d 0 /f"
    )

    if (Query-RegValue "$rootKey\Microsoft\Windows NT\CurrentVersion\NetworkList\DefaultMediaCost" Ethernet) {
        Steal-RegKey "$rootkey\Microsoft\Windows NT\CurrentVersion\NetworkList\DefaultMediaCost" | Out-Null
        # Set ethernet connections to be metered, to avoid frivolous downloads.
        $operations += ("reg add '$rootKey\Microsoft\Windows NT\CurrentVersion\NetworkList\DefaultMediaCost' /v Ethernet /t REG_DWORD /d 2 /f")
    }


    $operations | % { Run-Operation $_ } | Out-Null
    shoutOut "Done!" Green

        
    shoutOut "Unloading registry...." Cyan
    { reg unload $rootKey } | Run-Operation | Out-Null

}