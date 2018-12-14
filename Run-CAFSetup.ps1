# Collect, Analyze, Fix Setup

. "$PSScriptRoot\Common\ShoutOut.ps1"
. "$PSScriptRoot\Common\Run-Operation.ps1"
. "$PSScriptRoot\Common\New-PSCredential.ps1"
. "$PSScriptRoot\Common\Parse-ConfigFile.ps1"
. "$PSScriptRoot\Configure-NAT.ps1"
. "$PSScriptRoot\Create-VMSwitch.ps1"
. "$PSScriptRoot\CAF-VMs.ps1"


<#
.WISHLIST
    - Move iterating over the VMPaths to CAF-VMs and operate on VHDs/VMs from all paths at once. [Done]
    - Decouple Rearm-VMs from CAF-VHDs by having CAF-VMs decide which VMs should be rearmed instead of Rearm-VMs.
.SYNOPSIS
    Collects, analyzes and makes fixes to VMs and their associated VHDs
#>
function Run-CAFSetup {
    param(
        $Configuration,
        [Switch]$SkipVMRearm
    )

    if ($Configuration -is [System.Management.Automation.ErrorRecord]) {
        shoutOut "Unable to load the configuration file! Aborting CAFSetup" Red
        return
    }

    $networks = $Configuration.Keys | ? { $_ -match "^Network" } 

    shoutOut "Configuring VMSwitches..." Cyan
    $networks | % {
        Create-VMSwitch $_ $Configuration[$_]
    }

    ShoutOUt "Configuring NAT..."
    Configure-NAT $Configuration

    if ($VMFolders = @($conf.HyperVStep.VMPath) + @($conf.Global.VMPath) | ? { $_ }) {
        shoutOut "CAFing VMs in '$( $VMFolders -join ", " ) '"
        $ExcludePaths = @($conf.HyperVStep.VMPathExclude) + @($conf.Global.VMPathExclude) | ? { $_ }
        
        CAF-VMs -VMFolders $VMFolders -Configuration $Configuration -ExcludePaths $ExcludePaths -NoRearm:$SkipVMRearm
    }
}