#requires -Modules ShoutOut


function _configureNAT {
    param($configuration)

    if (!$configuration) {
        shoutOut "No configuration object provided, Skipping NAT configuration." Warning
        return
    }

    $NATConfig = $configuration.NAT
    $NATNetworks = $configuration.GetEnumerator() | ? { $_.key -match "Network" -and ($_.Value.ContainsKey("Type") -and $_.Value.Type -eq "NAT") }
    
    if (!($NATConfig -or $NATNetworks)) {
        shoutOut "No NAT options specified, skipping NAT configuration."
        return
    }
    
    $NetNatAvailable = (Get-Module -ListAvailable NetNat) -ne $null
    $NetNatLoaded    = (Get-Module NetNat) -ne $null

    if ($NetNatAvailable) {
        shoutOut "NetNat module is available."
        if (!$NetNatLoaded) {
            shoutOut "Importing NetNat module..."
            Import-Module NetNat
        } else {
            shoutOut "NetNat module imported."
        }
    } else {
        shoutOut "NetNat module is not available."
    }

    if ($NetNatAvailable) {
        
        shoutOut "Configuring NAT using: WinNAT"

        shoutOut "Building NAT definition..."
        $natDefinition = @{
            Name="HostNat"
            ErrorAction="Stop"
        }

        # This assumes that we only wish to use physical adapters,
        # and not adapters associated with External VMSwitches.
        $physAdapters = Get-NetAdapter -Physical | ? {
                $_.Status -eq "Up" # Adapters may have been assigned
                                   # a static IP, so we filter them out
                                   # firs to save time.
            } | ? {
                $_ | Get-NetIPAddress -ea SilentlyContinue
            }

        if (!$physAdapters) {
            shoutOut "No physical adapters available for NAT!"
            shoutOut "Aborting WinNAT configuration."
            return
        }

        $connections = $physAdapters | Get-NetIPAddress -AddressFamily IPv4 | % {
            $pl = $_.PrefixLength
            $mask = [Math]::Pow(2, 32) - [Math]::Pow(2, (32 - $pl))
            $bytes = [BitConverter]::GetBytes([UInt32] $mask)
            $netmask = [IPAddress]( (($bytes.Count - 1)..0 | ForEach-Object { [String] $bytes[$_] }) -join "." )
            $ip = [IPAddress] $_.IPAddress
            
            $subnet = [IPAddress]($ip.Address -band $netmask.Address)
            @{Address=$_.IPAddress;Prefix="$subnet/$pl"}
        }

        $externalConnection = @($connections)[0]
        $selectedPrefix = $externalConnection.Prefix
        $natDefinition.ExternalIPInterfaceAddressPrefix = $selectedPrefix

        if ($NATConfig) {
            shoutOut "Applying global NAT settings..."

            $NATConfig.Keys | % {
                $natDefinition[$_] = $NATConfig[$_]
            }
        }

        shoutOut "Finished building NAT definition:"
        shoutOut $natDefinition

        if (Get-NetNat $natDefinition.Name -ea SilentlyContinue) {
            shoutOut "There is an existing NAT with this name, removing it and building anew..."
            Remove-NetNat -Name $natDefinition.Name -Confirm:$false
        }

        try {
            New-NetNat @natDefinition -Confirm:$false | Out-Null
            Add-NetNatExternalAddress -NatName $natDefinition.Name -IPAddress $externalConnection.Address -PortStart 44000 -PortEnd 48000 | Out-Null
        } catch {
            ShoutOut "Failed to create a new NAT!" Red
            shoutOut $_
        }

        if ($NATNetworks) {
            # Unclear if this section is needed.
        }

        shoutOut "Finished WinNAT configuration pass."
    } else {
        shoutOut "Failed to configure NAT, the NetNat module is unavailable"
    }
}