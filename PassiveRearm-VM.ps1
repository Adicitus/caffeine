
. "$PSScriptRoot\Common\Find-VolumePath.ps1"
. "$PSScriptRoot\Common\Query-RegValue.ps1"
. "$PSScriptRoot\Common\Set-RegValue.ps1"
. "$PSScriptRoot\Common\ShoutOut.ps1"


# ! WARNING: This function does not seem to perform as expected and may corrupt the registries of the VMs being rearmed ! #
function PassiveRearm-VM {
    param(
        $vm,
        $credentialEntry = @{
            Domain="Adatum"
            Username="Administrator"
            Password='Pa55w.rd'
        }
    )

    shoutOut ("Attempting Passive Rearm: $($vm.VMName) ".PadRight(80,'=')) Magenta

    $offlineSoftwareMP = "HKLM\OFFLINE-SOFTWARE"
    $vhdCooldownTimeout = 5000

    $vhds = $vm | Get-VMHardDiskDrive

    $dism = "$PSScriptRoot\bin\DISM\dism.exe"

    $regConfig = @{
        "$offlineSoftwareMP\CAFSetup\actions\OnRearm"= @{
            action=@{Original=$null;Config="alwaysShutdown"; Type="REG_SZ"}
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
                        $regConfig[$key][$value].Original = Query-RegValue $key $value
                        sleep -Milliseconds 100
                        Set-RegValue $key $value $regConfig[$key][$value].Config $regConfig[$key][$value].Type
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
    $rearmTimeout1 = 120000
    $rearmTimeout2 = 180000
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
                            Set-RegValue $key $value $regConfig[$key][$value].Original
                        } else {
                            { reg delete $key /v $value /f } | Run-Operation
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