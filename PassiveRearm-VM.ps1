
. "$PSScriptRoot\Common\Find-VolumePath.ps1"
. "$PSScriptRoot\Common\Query-RegValue.ps1"
. "$PSScriptRoot\Common\Set-RegValue.ps1"

# ! WARNING: This function does not seem to perform as expected and may corrupt the registries of the VMs being rearmed ! #
function PassiveRearm-VM {
    param($vm)

    $offlineSoftwareMP = "HKLM\OFFLINE-SOFTWARE"
    $vhdCooldownTimeout = 5000

    $vhds = $vm | Get-VMHardDiskDrive

    $dism = "$PSScriptRoot\bin\DISM\dism.exe"

    $regConfig = @{
        "$offlineSoftwareMP\CAFSetup\actions\OnRearm"= @{
            action=@{Original=$null;Config="alwaysShutdown"; Type="REG_SZ"}
        }
        "$offlineSoftwareMP\Microsoft\Windows NT\CurrentVersion\Winlogon" = @{
            AutoAdminLogon  = @{ Original=$null; Config=1; Type="REG_DWORD" }
            DefaultUserName = @{ Original=$null; Config="Administrator"; Type="REG_SZ" }
            DefaultPassword = @{ Original=$null; Config='Pa$$w0rd'; Type="REG_SZ" }
            AutoLogonCount = @{ Original=$null; Config=1; Type="REG_DWORD" }
        }
    }

    foreach($vhd in $vhds){

        $vhd | Mount-VHD
        $vhd = $vhd | Get-VHD
        
        sleep -Milliseconds $vhdCooldownTimeout # sleep to avoid timing error between the mounting of the VHD and loading the registry.

        $disk = $vhd | Get-Disk
        $partitions = $disk | Get-Partition

        foreach($partition in $partitions) {
            $volume = $partition | Get-Volume
            $path = Find-VolumePath $volume

            if ( !(Test-Path "${Path}Windows\System32\Config\SOFTWARE") ) {
                Write-Host "Skip"
                continue
            } else {
                Write-host "System volume"
                { reg load $offlineSoftwareMP "${Path}Windows\System32\Config\SOFTWARE" } | Run-Operation -OutNull

                foreach( $key in $regConfig.Keys ) {
                    foreach ($value in $regConfig[$key].Keys) {
                        $regConfig[$key][$value].Original = Query-RegValue $key $value
                        Set-RegValue $key $value $regConfig[$key][$value].Config
                    }
                }

                { reg unload $offlineSoftwareMP } | Run-Operation -OutNull

                sleep -Milliseconds $vhdCooldownTimeout # sleep to avoid timing error between the dismounting of the VHD and unloading the registry.
            }
        }

        $vhd | Dismount-VHD
        $regConfig
    }

    # Start the VM to let CAF-GuestMachine run.
    $rearmTimeout = 120000
    $rearmStart = Get-Date
    $vm | Start-VM
    $vm = $vm | Get-VM
    while ($vm.state -eq "Running") {
        $duration = (Get-Date) - $rearmStart
        if ($duration.TotalMilliseconds -ge $rearmTimeout) {
            $vm | Stop-VM -TurnOff -Force
            break
        }
        sleep -Milliseconds 100
        $vm = $vm | Get-VM
    }

    sleep -Milliseconds $vhdCooldownTimeout

    foreach($vhd in $vhds){

        $vhd | Mount-VHD
        $vhd = $vhd | Get-VHD
        
        sleep -Milliseconds $vhdCooldownTimeout # sleep to avoid timing error between the mounting of the VHD and loading the registry.

        $disk = $vhd | Get-Disk
        $partitions = $disk | Get-Partition

        foreach($partition in $partitions) {
            $volume = $partition | Get-Volume
            $path = Find-VolumePath $volume

            if ( !(Test-Path "${Path}Windows\System32\Config\SOFTWARE") ) {
                Write-Host "Skip"
                continue
            } else {
                Write-host "System volume"
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

                { reg unload $offlineSoftwareMP } | Run-Operation -OutNull
                
                sleep -Milliseconds $vhdCooldownTimeout # sleep to avoid timing error between the dismounting of the VHD and unloading the registry.
            }
        }

        $vhd | Dismount-VHD
        $regConfig
    }
}