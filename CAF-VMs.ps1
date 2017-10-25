. "$PSScriptRoot\Common\Parse-ConfigFile.ps1"
. "$PSScriptRoot\Common\Rebase-VHDFiles.ps1" -Import
. "$PSScriptRoot\CAF-VHDs.ps1"
. "$PSScriptRoot\Rearm-VMs.ps1"


function CAF-VMs {
    param(
        [parameter(Mandatory=$false, Position=1)]$VMFolders='C:\Program Files\Microsoft Learning',
        [parameter(Mandatory=$false, position=2)]$Configuration = @{  },
        [Switch]$NoRearm
    )


    shoutOut "VMPaths:" Cyan
    $VMFolders | % { "'$_'" } | shoutOut

    shoutOut "Rebasing VHDs to ensure that all chains are complete..." Cyan
    Rebase-VHDFiles $VMFolders

    shoutOut "Inventorying VHDs..." Cyan
    $autorunFiles = @( (ls "$PSScriptRoot\CAFAutorunFiles\*" | % { $_.FullName }) ) + @("$PSScriptRoot\CAF-Guestmachine.ps1")
    $VHDRecords = CAF-VHDs $VMFolders -Configuration $Configuration -AutorunFiles $autorunFiles

    shoutOut "Creating VHD lookup table..." Cyan
    $VHDRecordLookup = @{}
    $VHDRecords | % {
        $VHDRecordLookup[$_.File] = $_
    }
    shoutOut "Done!" Green
     
    shoutOut "Collecting VM files..." Cyan
    $vmfiles = ls -Recurse $VMFolders | ? { $_.FullName -match ".*[\\/]Virtual Machines[\\/].+\.(exp|vmcx|xml)$" }
    shoutOut "Done!" Green
    shoutOut "Collected $($vmfiles.Count) VM files..." Cyan

    if ($Configuration.HyperVStep.ImportExclusionPath -or $Configuration.HyperVStepFilter.Exclude) {
        shoutOut "Checking against exclusion paths..."
        $exclusionList = @($Configuration.HyperVStep.ImportExclusionPath) + @($Configuration.HyperVStepFilter.Exclude)
        $vmfiles = $vmfiles | ? { $f = $_.FullName; !( $exclusionList | ? { $f -like "$_*" }  ) }
        shoutOut " Done!" Green
        shoutOut "kept $($vmfiles.Count) VM files..." Cyan
    }

    shoutOut "Checking for incompatibilities..." Cyan
    $compatibilityReports = $vmfiles | % {
        $file = $_.FullName

        $r = { Compare-VM -Path $file -ErrorAction Stop } | Run-Operation
        if ($r -is [System.Management.Automation.ErrorRecord]) {
            switch -Wildcard ($r) {
                "*Identifier already exists.*" {
                    shoutOut "'$file' belongs to an already imported VM!" Green
                    break
                }
                "*Object is in use*" {
                    shoutOut "'$file' seems to belong to aleady imported VM" Yellow
                    break
                }
                default {
                    shoutOut "An unknown error occured when trying to inspect '$file':" Red
                    shoutOut $r Red
                }
            }
        } else { return $r }
    }
    $compatibilityReports | ? { $_.Incompatibilities } | % { 
        shoutOut "Incompatibilities for '$($_.Path)' ('$($_.VM.VMName)'):" Cyan
        $_.Incompatibilities | % {
            shoutOut ("{0,-15} {1}" -f "$($_.Source)':",$_.Message) Red
        }
    }
    shoutOut "Done!" Green

    shoutOut "Importing any unimported compatible VMs..." Cyan
    $r = $compatibilityReports | ? { !$_.Incompatibilities } | % {
        shoutOut "Importing '$($_.Path)' ('$($_.VM.VMName)')..."; $_
    } | % { { Import-VM -Path $_.Path } | Run-Operation }
    
    shoutout "Done!" Green

    shoutOut "Checking which machines need to be rearmed..." Cyan
    $vms = Get-VM
    
    $VMsToRearm = $vms | % {
        shoutOut ("{0}..." -f $_.VMName) -NoNewline
        $_
    } | ? {
        $VMName = $_.VMName
        # Check if the VM should be rearmed
        $r1 = ($Configuration["CAF-VMs"].NoRearm | ? { $_ -and ($VMName -match $_) }) -eq $null
        $r2 = ($Configuration["CAF-VMs"].Rearm   | ? { $_ -and ($VMName -match $_) }) -eq $null
        $NoRearm = ( $r1 -and !$r2 )

        if ($NoRearm) {
            shoutOut "Is marked as 'NoRearm'."  Green
        }

        return !$NoRearm
    } | ? {
        # Check if the VM has at least one disk containing a Windows installation:
        $disks = $_ | Get-VMHardDiskDrive
        foreach ($disk in $disks) {
            if ($record = $VHDRecordLookup[$disk.Path]) {
                if ( $record.ContainsKey("WindowsEdition") ) {
                    return $true
                }
            }
        }
        shoutOut "Does not have a known Windows installation." Yellow
        return $false
    } | % {
        shoutOut "Needs rearm!" Red
        $_
    }

    if (!$NoRearm) {
        if ($VMsToRearm -and ($VMsToRearm.Count -gt 0)) {
            shoutOUt "Rearming $( ($VMsToRearm | % { $_.VMName }) -join ", " )"
            Rearm-VMs $VMsToRearm $Configuration
        } else {
            shoutOut "No VMs need to be rearmed."
        }
    }

    Get-VM | % {
        $vm = $_

        if (!($vm | Get-VMSnapshot)) {
            shoutOut "Adding a snapshot to '$($vm.VMName)'..."
            { $vm | Checkpoint-VM -SnapshotName "Initial Snapshot" } | Run-Operation | Out-Null
            shoutOut "Done!" Green
        }
    }
}