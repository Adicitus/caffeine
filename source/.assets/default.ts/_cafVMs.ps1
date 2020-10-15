#requires -Modules ACGCore

. "$PSScriptRoot\_cafVHDs.ps1"
. "$PSScriptRoot\_rearmVMs.ps1"


function _cafVMs {
    param(
        [parameter(Mandatory=$false, Position=1)]$VMFolders='C:\Program Files\Microsoft Learning',
        [parameter(Mandatory=$false, position=2)]$Configuration = @{  },
        [parameter(Mandatory=$false, Position=3)]$ExcludePaths = @(),
        [Switch]$NoRearm
    )


    shoutOut "VMPaths:"
    $VMFolders | % { "'$_'" } | shoutOut

    shoutOut "Rebasing VHDs to ensure that all chains are complete..."
    Rebase-VHDFiles $VMFolders

    shoutOut "Inventorying VHDs..."
    $VHDRecords = _cafVHDs $VMFolders -Configuration $Configuration -ExcludePaths $ExcludePaths

    shoutOut "Creating VHD lookup table..."
    $VHDRecordLookup = @{}
    $VHDRecords | % {
        $VHDRecordLookup[$_.File] = $_
    }
    shoutOut "Done!" Success
     
    shoutOut "Collecting VM files..."
    $t = ls -Recurse $VMFolders | ? { $_.FullName -match ".*[\\/]Virtual Machines[\\/].+\.(exp|vmcx|xml)$" }
    $t = $t | ? { $p = $_.FullName; -not ($excludePaths | ? { $p -like $_ }) }
    shoutOut ("Found {0} files..." -f @($t).Count)
    $VMFiles = $t | Sort -Property FullName | Get-Unique
    shoutOut ("{0} non-duplicates..." -f @($VMFiles).Count)

    shoutOut "Done!" Success

    shoutOut "Collected $($vmfiles.Count) VM files..."

    if ($Configuration["CAF-VMs"].NoImport) {
        shoutOut "Checking against exclusion paths..."
        $exclusionList = @($Configuration["CAF-VMs"].NoImport)
        $vmfiles = $vmfiles | ? { $f = $_.FullName; !( $exclusionList | ? { $f -like "$_*" }  ) }
        shoutOut " Done!" Green
        shoutOut "Kept $($vmfiles.Count) VM files..."
    }

    shoutOut "Checking for incompatibilities..."
    $compatibilityReports = $vmfiles | % {
        $file = $_.FullName

        $r = { Compare-VM -Path $file -ErrorAction Stop } | Run-Operation
        if ($r -is [System.Management.Automation.ErrorRecord]) {
            switch -Wildcard ($r) {
                "*Identifier already exists.*" {
                    shoutOut "'$file' belongs to an already imported VM!" Success
                    break
                }
                "*Object is in use*" {
                    shoutOut "'$file' seems to belong to aleady imported VM" Warning
                    break
                }
                default {
                    shoutOut "An unknown error occured when trying to inspect '$file':" Error
                    shoutOut $r
                }
            }
        } else { return $r }
    }
    $compatibilityReports | ? { $_.Incompatibilities } | % { 
        shoutOut "Incompatibilities for '$($_.Path)' ('$($_.VM.VMName)'):"
        $_.Incompatibilities | % {
            shoutOut ("{0,-15} {1}" -f "$($_.Source)':",$_.Message) Error
        }
    }
    shoutOut "Done!" Success

    shoutOut "Importing any unimported compatible VMs..."
    $r = $compatibilityReports | ? { !$_.Incompatibilities } | % {
        shoutOut "Importing '$($_.Path)' ('$($_.VM.VMName)')..."; $_
    } | % { { Import-VM -Path $_.Path } | Run-Operation }
    
    shoutout "Done!" Success

    shoutOut "Checking which machines need to be rearmed..."
    $vms = Get-VM
    
    $VMsToRearm = $vms | % {
        shoutOut ("{0}..." -f $_.VMName) -NoNewline
        $_
    } | ? {
        $VMName = $_.VMName
        # Check if the VM should be rearmed
        $r1 = ($Configuration["CAF-VMs"].NoRearm | ? { $_ -and ($VMName -match $_) }) -ne $null
        $r2 = ($Configuration["CAF-VMs"].Rearm   | ? { $_ -and ($VMName -match $_) }) -ne $null
        $NoRearm = ( $r1 -and !$r2 )

        if ($NoRearm) {
            shoutOut "Is marked as 'NoRearm'." 
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
        shoutOut "Does not have a known Windows installation." Warning
        return $false
    } | % {
        shoutOut "Needs rearm!" Warning
        $_
    }

    if (!$NoRearm) {
        if ($VMsToRearm -and ($VMsToRearm.Count -gt 0)) {
            shoutOUt "Rearming $( ($VMsToRearm | % { $_.VMName }) -join ", " )"
            _rearmVMs $VMsToRearm $Configuration
        } else {
            shoutOut "No VMs need to be rearmed."
        }
    }

    Get-VM | % {
        $vm = $_

        if (!($vm | Get-VMSnapshot)) {
            shoutOut "Adding a snapshot to '$($vm.VMName)'..."
            { $vm | Checkpoint-VM -SnapshotName "Initial Snapshot" } | Run-Operation | Out-Null
            shoutOut "Done!" Success
        }
    }
}