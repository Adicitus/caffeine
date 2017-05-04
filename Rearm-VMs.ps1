

$script:_CAFScriptPath = "$PSScriptRoot\CAF-GuestMachine.ps1"
$script:_CAFScript = Get-Content $script:_CAFScriptPath
$script:_CAFBlock = [scriptblock]::Create($rearmScript)

function Rearm-VMs {
    param(
        [parameter(position=1)]$VHDRecordLookup,
        [parameter(position=2)]$Credentials
    )
    shoutOut "Checking which machines need to be rearmed..." Cyan
    $vms = Get-VM
    $VMsToCheck = $vms | ? {
        
        $disks = $_ | Get-VMHardDiskDrive
        foreach ($disk in $disks) {
            if ($record = $VHDRecordLookup[$disk.Path]) {
                if ( $record.WindowsEdition ) {
                    return $true
                }
            }
            return $false
        }
    }

    $VMsToCheck | % {
        shoutOut "Starting '$($_.VMName)'..." Cyan
        
        $r = { $_ | Start-VM } | Run-Operation
        if ($r -is [System.Management.Automation.ErrorRecord]) {
            shoutOut "Unable to start $($_.VMName)!" Red
            return 
        }

        $waitTimeout = 120000 #(2min)
        $waitStart = Get-Date

        $vm = Get-VM -Name $_.VMName
        while ($vm.Heartbeat -notlike "OK*") {
            Start-Sleep -Milliseconds 20
            $timeWaited = ((Get-Date) - $waitStart).TotalMilliseconds
            if ( $timeWaited -ge $waitTimeout ) {
                shoutOut "$($vm.VMName) timed out while waiting for heartbeat... (waited ${timeWaited}ms, $($_.Heartbeat))" Red
                $vm | Stop-Vm -TurnOff -Force
                return
            }
            $vm = Get-VM -Name $vm.VMName
        }
        shoutout "$($vm.Heartbeat)" Green
        $waitStart = Get-Date

        shoutOut "Waiting for network adapters..." Cyan -NoNewline
        $netAdapterTimedout = $false
        $vmadapters = $vm | Get-VMNetworkAdapter
        while ( ($vmadapters | ? { !$_.IPAddresses }) -and !$netAdapterTimedout) {
            $timeWaited = ((Get-Date) - $waitStart).TotalMilliseconds
            if ( $timeWaited -ge $waitTimeout ) {
                shoutOut "$($_.VMName) timed out while waiting for Network adapters.... (waited ${timeWaited}ms, $($_.Status))" Red
                $netAdapterTimedout = $true;
            }
            $vmadapters = $vm | Get-VMNetworkAdapter
        }

        if (!($vmadapters | ? { !$_.IPAddresses })) {
            shoutOut "All network adapters initialized! (waited ${timeWaited}ms, $($_.Status))" Green
        }
        $ipaddresses = $vm | Get-VMNetworkAdapter | % { $_.IPAddresses }
        shoutOut "Found the following IP addresses: $($ipaddresses -join ", ")"

        $activeAddresses = $ipaddresses | ? {
            $ping = Get-WmiObject -Query "Select * from Win32_PingStatus Where Address='$_'"
            $ping.StatusCode -eq 0
        }

        shoutOut "Active addresses: $($activeAddresses -join ", ")"
        <#
        $rearmBlock = {
            $Env:COMPUTERNAME
            $rearmFiles = ls -Recurse "$Env:ProgramFiles" -Filter "*ospprearm.exe" | % { $_.FullName }
            $rearmFiles | write-host $_
            $r = $rearmFiles | % { & $_ } *>&1
            
            $licenses = Get-WmiObject SoftwareLicensingProduct | ? { $_.PartialProductKey -and ( ($_.LicenseStatus -eq 5) -or ( ($_.GracePeriodRemaining / (24 * 60)) -lt 9.0 ) ) }
            $licenses | % {
                "$($_.Description) ($($_.LicenseFamily)): $($_.LicenseStatus) ($($_.GracePeriodRemaining) minutes left, $($_.RemainingSkuReArmCount) SKU rearms left)"
                
                try {
                    if ($_.Licensefamily -match "Office|Eval") {
                        $_.ReArmSku() *>&1
                    }
                    sleep 10
                } catch {
                    $_
                }
                
            }
        }
        #>

        $successfulConnection = $false
        if (Get-Command "Invoke-Command" | ? { $_.Parameters.Keys.Contains("VMName") }) {
            shoutOut "Trying to connect using VM name..." Cyan
            $Credentials | % {
                if ($successfulConnection) { return }
                $credential = $_
                try {
                    $r = Invoke-Command -VMName $vm.VMName -Credential $_ -ScriptBlock $_CAFBlock -ErrorAction stop *>&1

                    shoutOut "Connected successfully using credentials for '$($credential.Username)'!" Green
                    $r | % { shoutOut "`t| $_" White }
                    $successfulConnection = $true
                } catch {
                    shoutOut "Unable to connect to '$($vm.VMname)' with credentials for '$($credential.Username)'" Red
                    shoutOut "`t| $($_)" White
                }
            }
        }

        if (!$successfulConnection) {
            $activeAddresses | % {
                if ($successfulConnection) { return }
                shoutOut "Attempting to connect using IP-Address ($_)..." Cyan
                $address = $_
                shoutOut "Connecting to '$address'..."
                $Credentials | % {
                    if ($successfulConnection) { return }
                    $credential = $_
                    try {
                        $r = Invoke-Command -ComputerName $address -Credential $_ -ScriptBlock $_CAFBlock -ErrorAction stop *>&1

                        shoutOut "Connected successfully using credentials for '$($credential.Username)'!" Green
                        $r | % { shoutOut "`t| $_" White }
                        $successfulConnection = $true
                    } catch {
                        shoutOut "Unable to connect with credentials for '$($credential.Username)'!" Red
                        shoutOut "`t| $($_)" White
                    }
                }
            }
        }
        
        if (!$successfulConnection) {
            shoutOut "Unable to connect to '$($vm.VMName)' for rearm!" Red
        }

        $vm
        
    } | % {
        shoutOut "Shutting down..." Cyan -NoNewline
        try {
            $vm | Stop-VM
            shoutOut "Done!" Green 
        } catch {
            shoutOut "Failed!" Red
            shoutOUt $_ Red
        }
    }

    shoutOut "VM Rearm check finished..." Green
}