. "$PSScriptRoot\Common\New-PSCredential.ps1"
. "$PSScriptRoot\Common\Parsing\Parse-ConfigFile.ps1"
. "$PSScriptRoot\Common\Rebase-VHDFiles.ps1" -Import
. "$PSScriptRoot\CAF-VHDs_v2.ps1"
. "$PSScriptRoot\Rearm-VMs_v2.ps1"


function CAF-VMs {
    param(
        [parameter(Mandatory=$false, Position=1)]$VMFolders='C:\Program Files\Microsoft Learning',
        [parameter(Mandatory=$false, Position=2)]$Credentials=@( 
            (New-PSCredential ".\Administrator" 'Pa$$w0rd'),
            (New-PSCredential ".\Admin" 'Pa$$w0rd'),
            (New-PSCredential ".\Administrator" 'Pa55w.rd'),
            (New-PSCredential ".\Admin" 'Pa55w.rd')
        ),
        [parameter(Mandatory=$false, position=3)]$Configuration = @{  },
        [Switch]$NoRearm
    )

    shoutOut "Rebasing VHDs to ensure that all chains are complete..." Cyan
    Rebase-VHDFiles $VMFolders

    shoutOut "Inventorying VHDs..." Cyan
    $VHDRecords = CAF-VHDs $VMFolders -Configuration $Configuration -AutorunFiles (  @( (ls "$PSScriptRoot\CAFAutorunFiles\*" | % { $_.FullName }) ) + @($script:_CAFScriptPath)  )

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

        $r = { Compare-VM -Path $_.FullName -ErrorAction Stop } | Run-Operation
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
        shoutout "Incompatibilities for '$($_.Path)' ('$($_.VM.VMName)'):" Cyan
        $_.Incompatibilities | % {
            shoutOut ("{0,-15} {1}" -f "$($_.Source)':",$_.Message) Red
        }
    }
    shoutout "Done!" Green

    shoutOut "Importing any unimported compatible VMs..." Cyan
    $r = $compatibilityReports | ? { !$_.Incompatibilities } | % {
        shoutOut "Importing '$($_.Path)' ('$($_.VM.VMName)')..."; $_
    } | % {  {Import-VM $_ } | Run-Operation }
    
    shoutout "Done!" Green

    shoutOut "Checking which machines need to be rearmed..." Cyan
    $vms = Get-VM
    # Check which VMs have at least one disk containing a Windows installation:
    $VMsToRearm = $vms | ? {
        
        $disks = $_ | Get-VMHardDiskDrive
        foreach ($disk in $disks) {
            if ($record = $VHDRecordLookup[$disk.Path]) {
                if ( $record.ContainsKey("WindowsEdition") ) {
                    return $true
                }
            }
            return $false
        }
    }

    if (!$NoRearm) {
        shoutOUt "Rearming $( ($VMsToRearm | % { $_.VMName }) -join ", " )"
        Rearm-VMs $VMsToRearm $Credentials
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