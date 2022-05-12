# Collect, Analyze, Fix Setup

#requires -Modules ACGCore

. "$PSScriptRoot\_configureNAT.ps1"
. "$PSScriptRoot\_createVMSwitch.ps1"
. "$PSScriptRoot\_cafVMs.ps1"


<#
.WISHLIST
    - Move iterating over the VMPaths to CAF-VMs and operate on VHDs/VMs from all paths at once. [Done]
    - Decouple Rearm-VMs from CAF-VHDs by having CAF-VMs decide which VMs should be rearmed instead of Rearm-VMs.
.SYNOPSIS
    Collects, analyzes and makes fixes to VMs and their associated VHDs
#>
function _runCAFSetup {
    param(
        $Configuration,
        [Switch]$SkipVMRearm
    )

    if ($Configuration -is [System.Management.Automation.ErrorRecord]) {
        shoutOut "Unable to load the configuration file! Aborting CAFSetup" Error
        return
    }

    $networks = $Configuration.Keys | Where-Object { $_ -match "^Network" } 

    shoutOut "Configuring VMSwitches..."
    $networks | ForEach-Object {
        _createVMSwitch $_ $Configuration[$_]
    }

    ShoutOUt "Configuring NAT..."
    _configureNAT $Configuration

    if ($VMFolders = @($conf.HyperVStep.VMPath) + @($conf.Global.VMPath) | Where-Object { $_ }) {
        shoutOut "CAFing VMs in '$( $VMFolders -join ", " ) '"
        $ExcludePaths = @($conf.HyperVStep.VMPathExclude) + @($conf.Global.VMPathExclude) | Where-Object { $_ }
        
        _cafVMs -VMFolders $VMFolders -Configuration $Configuration -ExcludePaths $ExcludePaths -SkipRearm:$SkipVMRearm
    }
}