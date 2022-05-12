#requires -Modules ACGCore

. "$PSScriptRoot\_cafVHDs.ps1"
. "$PSScriptRoot\_rearmVMs.ps1"


function _cafVMs {
    param(
        [parameter(Mandatory=$false, Position=1)]$VMFolders='C:\Program Files\Microsoft Learning',
        [parameter(Mandatory=$false, position=2)]$Configuration = @{},
        [parameter(Mandatory=$false, Position=3)]$ExcludePaths = @(),
        [Switch]$SkipRearm
    )


    shoutOut "VMPaths:"
    $VMFolders | ForEach-Object { "'$_'" } | shoutOut

    shoutOut "Rebasing VHDs to ensure that all chains are complete..."
    Rebase-VHDFiles $VMFolders

    shoutOut "Inventorying VHDs..."
    $VHDRecords = _cafVHDs $VMFolders -Configuration $Configuration -ExcludePaths $ExcludePaths

    shoutOut "Creating VHD lookup table..."
    $VHDRecordLookup = @{}
    $VHDRecords | ForEach-Object {
        $VHDRecordLookup[$_.File] = $_
    }
    shoutOut "Done!" Success
     
    shoutOut "Collecting VM files..."
    $t = Get-ChildItem -Recurse $VMFolders | Where-Object {
        $_.FullName -match ".*[\\/]Virtual Machines[\\/].+\.(exp|vmcx|xml)$"
    }
    $t = $t | Where-Object {
        $p = $_.FullName;
        -not ($excludePaths | Where-Object { $p -like $_ })
    }
    shoutOut ("Found {0} files..." -f @($t).Count)
    $VMFiles = $t | Sort-Object -Property FullName | Get-Unique
    shoutOut ("{0} non-duplicates..." -f @($VMFiles).Count)

    shoutOut "Done!" Success

    "Collected {0} VM files..." -f $vmfiles.Count | shoutOut

    if ($Configuration["CAF-VMs"].NoImport) {
        shoutOut "Checking against exclusion paths..."
        $exclusionList = @($Configuration["CAF-VMs"].NoImport)
        $vmfiles = $vmfiles | Where-Object {
            $f = $_.FullName;
            !( $exclusionList | Where-Object {
                $f -like "$_*"
            })
        }
        shoutOut " Done!" Success
        "Kept {0} VM files..." -f $vmfiles.Count | shoutOut
    }

    shoutOut "Checking for incompatibilities..."
    $compatibilityReports = $vmfiles | ForEach-Object {
        $file = $_.FullName

        $r = { Compare-VM -Path $file -ErrorAction Stop } | Invoke-ShoutOut
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
        } else {
            return $r
        }
    }

    $compatibilityReports | Where-Object {
        $_.Incompatibilities
    } | ForEach-Object {
        "Incompatibilities for '{0}' ('{1}'):" -f $_.Path, $_.VM.VMName | shoutOut
        $_.Incompatibilities | ForEach-Object {
            shoutOut ("{0,-15} {1}" -f "$($_.Source)':",$_.Message) Error
        }
    }
    shoutOut "Done!" Success

    shoutOut "Importing any unimported compatible VMs..."
    $r = $compatibilityReports | Where-Object {
        !$_.Incompatibilities
    } | ForEach-Object {
        shoutOut "Importing '$($_.Path)' ('$($_.VM.VMName)')..."
        $_
    } | ForEach-Object {
        { Import-VM -Path $_.Path } | Invoke-ShoutOut
    }
    shoutout "Done!" Success

    shoutOut "Checking which machines need to be rearmed..."
    $vms = Get-VM
    

    if (!$SkipRearm) {

        $VMsToRearm = $vms | ForEach-Object {
            shoutOut ("{0}..." -f $_.VMName) -NoNewline
            $_
        } | Where-Object {
            $VMName = $_.VMName
            # Check if the VM should be rearmed
            $r1 = $null -ne ($Configuration["CAF-VMs"].NoRearm | Where-Object {
                $_ -and ($VMName -match $_)
            })
            $r2 = $null -ne ($Configuration["CAF-VMs"].Rearm   | Where-Object {
                $_ -and ($VMName -match $_)
            })
            $NoRearm = ( $r1 -and !$r2 )

            if ($NoRearm) {
                shoutOut "Is marked as 'NoRearm'." 
            }

            return !$NoRearm
        } | Where-Object {
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
        } | ForEach-Object {
            shoutOut "Needs rearm!" Warning
            $_
        }

        if ($VMsToRearm -and ($VMsToRearm.Count -gt 0)) {
            "Rearming {0}" -f ( ($VMsToRearm | ForEach-Object { $_.VMName }) -join ", " ) | shoutOut
            _rearmVMs $VMsToRearm $Configuration
        } else {
            shoutOut "No VMs need to be rearmed."
        }
    }

    Get-VM | ForEach-Object {
        $vm = $_

        if (!($vm | Get-VMSnapshot)) {
            shoutOut "Adding a snapshot to '$($vm.VMName)'..."
            { $vm | Checkpoint-VM -SnapshotName "Initial Snapshot" } | Invoke-ShoutOut | Out-Null
            shoutOut "Done!" Success
        }
    }
}