﻿#requires -Modules ACGCore

# ! NOTE: This function needs to be carefully maintained, it should only return $true or $false. ! #
function _passiveRearmVM {
    param(
        $vm,
        $credentialEntry = @{
            Domain="Adatum"
            Username="Administrator"
            Password='Pa55w.rd'
        },
        $VhdCooldownTimeout = 5000,
        $RearmTimeout1 = 180000,
        $RearmTimeout2 = 240000
    )

    shoutOut ("Attempting Passive Rearm: $($vm.VMName) ".PadRight(80,'=')) Magenta
    shoutOut ("Credentials: {0}\{1}, {2}" -f $credentialEntry.Domain,$credentialEntry.Username,$credentialEntry.Password)

    $offlineSoftwareMP = "HKLM\OFFLINE-SOFTWARE"

    $vhds = $vm | Get-VMHardDiskDrive

    $dism = "$PSScriptRoot\bin\DISM\dism.exe"

    $regConfig = @{
        "$offlineSoftwareMP\CAFSetup\actions\OnRearm"= @{
            action=@{Original="promptRestart";Config="alwaysShutdown"; Type="REG_SZ"}
        }
        "$offlineSoftwareMP\Microsoft\Windows NT\CurrentVersion\Winlogon" = @{
            AutoAdminLogon  = @{ Original=$null; Config=1; Type="REG_SZ" }
            DefaultUserName = @{ Original=$null; Config=$credentialEntry.Username; Type="REG_SZ" }
            DefaultDomainName = @{ Original=$null; Config=$credentialEntry.Domain; Type="REG_SZ" }
            DefaultPassword = @{ Original=$null; Config=$credentialEntry.Password; Type="REG_SZ" }
            AutoLogonCount = @{ Original=$null; Config=1000; Type="REG_DWORD" }
        }
    }

    $success = $true

    shoutOut "Inspecting and modifying VHDs..."

    foreach($vhd in $vhds){
        shoutOut "Inspecting '$($vhd.path)'..."
        $vhd | Mount-VHD
        $vhd = $vhd | Get-VHD
        
        sleep -Milliseconds $vhdCooldownTimeout # sleep to avoid timing error between the mounting of the VHD and loading the registry.

        $disk = $vhd | Get-Disk
        $partitions = $disk | Get-Partition

        foreach($partition in $partitions) {
            shoutOut ("Checking partition #{0}..." -f $partition.PartitionNumber)
            $volume = $partition | Get-Volume
            $path = Find-VolumePath $volume

            if ( !(Test-Path "${Path}Windows\System32\Config\SOFTWARE") ) {
                shoutOut "No windows directory, Skip!"
                continue
            } else {
                shoutOut "Windows directory found!" Green
                shoutOut "Loading SOFTWARE registry..."
                { reg load $offlineSoftwareMP "${Path}Windows\System32\Config\SOFTWARE" } | Run-Operation -OutNull

                foreach( $key in $regConfig.Keys ) {
                    foreach ($value in $regConfig[$key].Keys) {
                        if ($regConfig[$key][$value].Original -eq $null) {
                            $regConfig[$key][$value].Original = Query-RegValue $key $value
                        }
                        sleep -Milliseconds 100
                        Set-RegValue $key $value $regConfig[$key][$value].Config $regConfig[$key][$value].Type | Out-Null
                        sleep -Milliseconds 100
                    }
                }

                shoutOut "Unloading SOFTWARE registry..."
                { reg unload $offlineSoftwareMP } | Run-Operation -OutNull

                sleep -Milliseconds $vhdCooldownTimeout # sleep to avoid timing error between the dismounting of the VHD and unloading the registry.
            }
        }

        shoutOut "Dismounting VHD..."
        $vhd | Dismount-VHD
        # $regConfig
    }

    # Start the VM to let CAF-GuestMachine run.
    $rearmStart = Get-Date
    
    shoutOut "Starting VM..."
    $vm | Start-VM

    shoutOut "Waiting for the VM to finish running..."
    $vm = $vm | Get-VM
    while ($vm.state -eq "Running") {
        $duration = (Get-Date) - $rearmStart
        if ($duration.TotalMilliseconds -ge $rearmTimeout1) {
            shoutOut "Rearm timed out! Shutting down..." Red
            $success = $false
            $vm | Stop-VM -Force
        }
        if ($duration.TotalMilliseconds -ge $rearmTimeout2) {
            shoutOut "Rearm timed out! Forcing TurnOff..." Red
            $vm | Stop-VM -TurnOff -Force
            break
        }
        sleep -Milliseconds 100
        $vm = $vm | Get-VM
    }
    shoutOut "VM has stopped."

    sleep -Milliseconds $vhdCooldownTimeout

    shoutOut "Restoring VHDs..."
    foreach($vhd in $vhds){
        shoutOut "Checking '$($vhd.path)'..."
        $vhd | Mount-VHD
        $vhd = $vhd | Get-VHD
        
        sleep -Milliseconds $vhdCooldownTimeout # sleep to avoid timing error between the mounting of the VHD and loading the registry.

        $disk = $vhd | Get-Disk
        $partitions = $disk | Get-Partition

        foreach($partition in $partitions) {
            shoutOut ("Checking partition #{0}" -f $partition.PartitionNumber)
            
            $volume = $partition | Get-Volume
            $path = Find-VolumePath $volume


            if ( !(Test-Path "${Path}Windows\System32\Config\SOFTWARE") ) {
                shoutOut "No windows directory, Skip!"
                continue
            } else {
                shoutOut "Windows directory found!" Green
                shoutOut "Loading SOFTWARE registry..."
                { reg load $offlineSoftwareMP "${Path}Windows\System32\Config\SOFTWARE" } | Run-Operation -OutNull

                foreach( $key in $regConfig.Keys ) {
                    foreach ($value in $regConfig[$key].Keys) {
                        if ( $regConfig[$key][$value].Original ) {
                            Set-RegValue $key $value $regConfig[$key][$value].Original | Out-Null
                        } else {
                            { reg delete $key /v $value /f } | Run-Operation -OutNull
                        }
                    }
                }

                shoutOut "Unloading SOFTWARE registry..."
                { reg unload $offlineSoftwareMP } | Run-Operation -OutNull
                
                sleep -Milliseconds $vhdCooldownTimeout # sleep to avoid timing error between the dismounting of the VHD and unloading the registry.
            }
        }
        
        shoutOut "Dismounting VHD..."
        $vhd | Dismount-VHD
        # $regConfig
    }
    shoutOut "Finished running passive rearm."

    return $success
}