#requires -Modules ACGCore

function _configureOfflineHKLM {
    param(
        [parameter(Mandatory=$true, Position=1)]$VHDMountDir,
        [parameter(Mandatory=$true, Position=2)]$Configuration
    )
    $rootKey = "HKLM\OFFLINE-SOFTWARE"
    shoutOut "Loading offline SOFTWARE hive..." Cyan
    {reg load $rootKey "$VHDMountDir\Windows\System32\config\SOFTWARE"} | Invoke-ShoutOut | Out-Null
    $r = {reg query "$rootKey\"} | Invoke-ShoutOut
    if (($r | ? { $_ -match "CAFSetup$" })) { "reg delete $rootKey\CAFSetup /f" | Invoke-ShoutOut | Out-Null; $r = "reg query `"$rootKey\`"" | Invoke-ShoutOut | Out-Null } #DEBUG
        
        
    if ( !($r | ? { $_ -match "CAFSetup$" }) ) {
            
        shoutOut "Setting up local CAF..."
        
        $operations = @(
            { reg add "$rootKey\CAFSetup" },
            { reg add $rootKey\CAFSetup /v AutorunDir /t REG_EXPAND_SZ /d C:\CAFAutorun },
            { reg add $rootKey\CAFSetup /v AutorunCount /t REG_DWORD /d 0 },
            
            { reg add "$rootKey\CAFSetup\Actions"},
            { reg add "$rootKey\CAFSetup\Actions\OnRearm"},
            { reg add "$rootKey\CAFSetup\Actions\OnRearm" /v action /t REG_SZ /d "promptRestart"}
            { reg query $rootKey\CAFSetup }
        )

        $operations | % { Invoke-ShoutOut $_ }  | Out-Null

        shoutOut "Done!" Success
    }

    if ( { reg query "$rootKey\Microsoft\Windows\CurrentVersion\RunOnce" | ? { $_ -match "^\s*CAFAutorunTrigger" } } | Invoke-ShoutOut |Out-Null) { shoutOut "Deleting old Trigger..." Cyan; { reg delete "$rootKey\Microsoft\Windows\CurrentVersion\Run" /v CAFAutorunTrigger /f } | Invoke-ShoutOut | Out-Null } #DEBUG

    
    $r = { reg query "$rootKey\Microsoft\Windows\CurrentVersion\RunOnce" } | Invoke-ShoutOut
    if ( !($r | ? { $_ -match "^\s*CAFAutorunTrigger" }) ) {
        shoutOut "Adding CAF autorun trigger..."
        { reg add "$rootKey\Microsoft\Windows\CurrentVersion\RunOnce" /v CAFAutorunTrigger /t REG_SZ /d "Powershell -WindowStyle Hidden -ExecutionPolicy Bypass -NonInteractive -NoProfile -NoLogo -Command ls C:\CAFAutorun -Filter '*.ps1' | ? { . `$_.FullName  }" } | Invoke-ShoutOut -OutNull

    }


    shoutOut "Making Quality of Life changes to hive..."

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


    $operations | % { Invoke-ShoutOut $_ } | Out-Null
    shoutOut "Done!" Success

        
    shoutOut "Unloading registry...."
    { reg unload $rootKey } | Invoke-ShoutOut | Out-Null

}