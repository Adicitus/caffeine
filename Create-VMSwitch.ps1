. "$PSScriptRoot\Common\RegexPatterns.ps1"

Function Create-VMSwitch{
    param(
        [parameter(Position=1)]$NetworkTitle,
        [parameter(Position=2)]$Config
    )

    if (!$config.Name) {
        shoutOut "No name given for '$NetworkTitle'!" Red
        shoutOut "Skip!"
        return
    }

    if ($s = { Get-VMSwitch | ? { $_.Name -eq $Config.Name }  } | Run-Operation) {
        $CurSwitch = $s
        { $CurSwitch | Set-VMSwitch -Notes "Modified during setup of '$NetworkTitle'." } | Run-Operation
    } else {
        $CurSwitch = { New-VMSwitch -Name $Config.Name -SwitchType Private } | Run-Operation
        { $CurSwitch | Set-VMSwitch -Notes "Automatically created during setup ('$NetworkTitle')." } | Run-Operation
    }

    if ($config.Type) {
        if ($CurSwitch.SwitchType -eq $config.Type) {
            shoutOut "$($CurSwitch.Name) is already $($config.type)!" Green 
        }else {
            shoutOut "$($CurSwitch.Name) is $($CurSwitch.SwitchType), needs to be $($config.type)!" Yellow
            switch ($Config.Type) {
                $null {
                    { $CurSwitch | Set-VMSwitch -SwitchType Private } | Run-Operation
                }
                Private {
                    { $CurSwitch | Set-VMSwitch -SwitchType Private } | Run-Operation
                }
                Internal {
                    { $CurSwitch | Set-VMSwitch -SwitchType Internal } | Run-Operation
                }
                External {
                    shoutOut "Selecting adapter..." Cyan
                    $adapters = { Get-NetAdapter -Physical -ErrorAction SilentlyContinue } | Run-Operation

                    $takenAdapters = Get-VMSwitch | ? { $_.NetAdapterInterfaceDescription } | % { $_.NetAdapterInterfaceDescription }

                    $adapters = { $adapters | ? { $_.InterfaceDescription -notin $takenAdapters } } | Run-Operation
            
                    if (!$adapters) {
                        shoutOut "No physical network adapters available for '$NetworkTitle'!" Red
                        shoutOut "Skip!"
                        return
                    }

                    $upAdapters =  $adapters | ? { $_.Status -eq 'Up' }
                    if (!$upAdapters) {
                        shoutOut "None of the available physical adapters seem to be connected!" Yellow
                    } else {
                        $adapters = $upAdapters
                    }

                    $adapter = $adapters | Select -first 1 | % { $_.InterfaceDescription }
                    { $CurSwitch |Set-VMSwitch -NetAdapterInterfaceDescription $adapter -AllowManagementOS $true} | Run-Operation
                }
                NAT {
                    shoutOut "NAT switches are not implemented at this time!" Yellow
                }
            }
        }
    }

    $CurSwitch = Get-VMSwitch $Config.Name

    if ($CurSwitch.SwitchType -eq "Private") {
        shoutOut "No further configuration will be done, since the switch is Private." Cyan
        shoutOut "Done!" Green
        return
    } else {
        shoutOut "Performing additional configuration..." Cyan
    }

    if ($config.IPAddress) {
        shoutOut "Checking if we're using the correct IP address" Cyan
        $adapter = Get-NetAdapter "*($($CurSwitch.Name))"
        $ipAddress = $adapter | Get-NetIPAddress | % { $_.IPAddress }

        if ( !($ipAddress -match $config.IPAddress) ) {
            shoutOut "Adding new IP address... ($($config.IPAddress))" Cyan
            $d = @{ }
            $d.IPAddress = $config.IPAddress
            if ($Config.Netmask -match $RegexPatterns.IPv4Netmask) {
                shoutOut "Using netmask '$($Config.Netmask)': " Cyan -NoNewline
                $bs = ($Config.Netmask -split "\." | % {
                    [Convert]::toString($_,2)
                }) -join ""
                shoutOut "$bs "
                $pl = ($bs -replace "0","").Length
                $d.PrefixLength = $pl
                shoutOut "($pl)"
            }
            
            { $adapter | New-NetIPAddress -IPAddress $Config.IPAddress -PrefixLength:$pl } | Run-Operation | Out-Null *> $null
        }
    }

    if ($conf.DefaultGateway) {
        # Add correct NetRoute.
    }

    shoutOut "Done!" Green
}