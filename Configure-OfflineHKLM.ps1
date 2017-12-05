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
        
        $operations = @(
            { reg add "$rootKey\CAFSetup" },
            { reg add $rootKey\CAFSetup /v AutorunDir /t REG_EXPAND_SZ /d C:\CAFAutorun },
            { reg add $rootKey\CAFSetup /v AutorunCount /t REG_DWORD /d 0 },
            
            { reg add "$rootKey\CAFSetup\Actions"},
            { reg add "$rootKey\CAFSetup\Actions\OnRearm"},
            { reg add "$rootKey\CAFSetup\Actions\OnRearm" /v action /t REG_SZ /d "promptRestart"}
            { reg query $rootKey\CAFSetup }
        )

        $operations | % { Run-Operation $_ }  | Out-Null

        shoutOut "Done!" Green
    }

    if ( { reg query "$rootKey\Microsoft\Windows\CurrentVersion\RunOnce" | ? { $_ -match "^\s*CAFAutorunTrigger" } } | Run-Operation |Out-Null) { shoutOut "Deleting old Trigger..." Cyan; { reg delete "$rootKey\Microsoft\Windows\CurrentVersion\Run" /v CAFAutorunTrigger /f } | Run-Operation | Out-Null } #DEBUG

    
    $r = { reg query "$rootKey\Microsoft\Windows\CurrentVersion\RunOnce" } | Run-Operation
    if ( !($r | ? { $_ -match "^\s*CAFAutorunTrigger" }) ) {
        shoutOut "Adding CAF autorun trigger..." Cyan
        { reg add "$rootKey\Microsoft\Windows\CurrentVersion\RunOnce" /v CAFAutorunTrigger /t REG_SZ /d "cmd /C start Powershell -WindowStyle Hidden -ExecutionPolicy Bypass -NonInteractive -NoProfile -NoLogo -Command ls C:\CAFAutorun -Filter '*.ps1' | ? { . `$_.FullName  }" } | Run-Operation -OutNull
    }


    shoutOut "Making Quality of Life changes to hive..." Cyan

    $operations = @(
        # Prevent UAC consent prompts for admins, as described @ http://www.ghacks.net/2013/06/20/how-to-configure-windows-uac-prompt-behavior-for-admins-and-users/
        "reg add $rootKey\Microsoft\Windows\CurrentVersion\Policies\System /v ConsentPromptBehaviorAdmin /t REG_DWORD /d 0 /f"
    )
    

    # Set connection metering to controlled frivolous downloads by Windows Update:


    if (Query-RegValue "$rootKey\Microsoft\Windows NT\CurrentVersion\NetworkList\DefaultMediaCost" Ethernet) {
        
        $ethernetCost = switch ($configuration.VMConfiguration.EthernetCost) {
            "Free" { 1 }
            "Metered" { 2 }
            default { 2 }
        }

        Steal-RegKey "$rootkey\Microsoft\Windows NT\CurrentVersion\NetworkList\DefaultMediaCost" | Out-Null
        # Set ethernet connections to be metered, to avoid frivolous downloads.
        $operations += ("reg add '$rootKey\Microsoft\Windows NT\CurrentVersion\NetworkList\DefaultMediaCost' /v Ethernet /t REG_DWORD /d $ethernetCost /f")
    }


    $operations | % { Run-Operation $_ } | Out-Null
    shoutOut "Done!" Green

        
    shoutOut "Unloading registry...." Cyan
    { reg unload $rootKey } | Run-Operation | Out-Null

}