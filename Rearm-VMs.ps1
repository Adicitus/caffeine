. "$PSScriptRoot\Common\New-PSCredential.ps1"
. "$PSScriptRoot\Common\ActiveRearm-VM.ps1"
. "$PSScriptRoot\PassiveRearm-VM.ps1"

function Rearm-VMs {
    param(
        [parameter(position=1)]$VMs,
        [parameter(position=2)]$Configuration = @{ }
    )

    shoutOut "Selecting Credentials... "
    $credentialEntries = if ($credentialKeys = $Configuration.Keys -match "^Credential") {
        $credentialKeys | % { $Configuration[$_] }
    } else {
        @(
            @{
                Domain="."
                Username="Administrator"
                Password='Pa$$w0rd'
                VMs="*"
            }
            @{
                Domain="."
                Username="Admin"
                Password='Pa$$w0rd'
                VMs="*"
            }
            @{
                Domain="."
                Username="Administrator"
                Password='Pa55w.rd'
                VMs="*"
            }
            @{
                Domain="."
                Username="Admin"
                Password='Pa55w.rd'
                VMs="*"
            }
        )
    }

    $Credentials = $credentialEntries | % {
        if (!$_.Username -or !$_.Password) {
            return
        }

        if (!$_.VMs) {
            $_.VMs = "*"
        }

        $domain = if ($_.Domain) { $_.Domain } else { "." }
        $c = New-PSCredential ("{0}\{1}" -f $_.Domain,$_.UserName) $_.Password
        $_.Credential = $c
        return $c
    }

    $MaintenanceSwitchName = "Maintenance"

    shoutOut "Adding '$MaintenanceSwitchName' switch..." Cyan
    $MaintenanceSwitch = New-VMSwitch -Name $MaintenanceSwitchName -SwitchType "Internal"

    $VMs | % {
        
        $vm = $_

        $success = $false # ActiveRearm-VM $vm $Credentials $MaintenanceSwitch

        if (!$success) {
            $applicableEntries = $credentialEntries | ? { $_.Credential -and ($vm.VMName -match $_.VMs) }
            foreach ($entry in $applicableEntries) {
                $success = PassiveRearm-VM $vm $entry
                if ($success) { break }
            }
        }
        
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