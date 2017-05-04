. "$PSScriptRoot\Common\ActiveRearm-VM.ps1"

function Rearm-VMs {
    param(
        [parameter(position=1)]$VMs,
        [parameter(position=2)]$Credentials
    )

    $MaintenanceSwitchName = "Maintenance"

    shoutOut "Adding '$MaintenanceSwitchName' switch..." Cyan
    $MaintenanceSwitch = New-VMSwitch -Name $MaintenanceSwitchName -SwitchType "Internal"

    $VMs | % {
        
        $vm = $_

        $success = ActiveRearm-VM $vm $Credentials $MaintenanceSwitch

        #TODO: Add MOCSetup-style passive rearm.
        
        if (!$success) {
            shoutOut "Failed to rearm '$($vm.VMName)'!" Red
            $notes = $vm.Notes
            $vm | Set-VM -Notes "REARM FAILED DURING SETUP, this machine may need to be rearmed manually.`n$notes"
        }
    }

    shoutOut "Removing '$MaintenanceSwitchName' switch..." Cyan
    $MaintenanceSwitch | Remove-VMSwitch -Force

    shoutOut "VM Rearm check finished..." Green
}