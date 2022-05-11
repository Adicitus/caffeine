#requires -Modules ACGCore
. "$PSScriptRoot\_passiveRearmVM.ps1"

function _rearmVMs {
    param(
        [parameter(position=1)]$VMs,
        [parameter(position=2)]$Configuration = @{ }
    )

    shoutOut "Selecting Credentials... " Cyan
    $credentialEntries = $Configuration.Keys -match "^Credential" | ? {
        $entry = $Configuration[$_]
        return $entry -is [hashtable] -and $entry.ContainsKey("VMs")
    } | % { $Configuration[$_] }

    if (-not $credentialEntries) {
        shoutOut "No VM credentials found, using defaults."
        $credentialEntries = @(
            @{
                Domain="."
                Username="Administrator"
                Password='Pa$$w0rd'
                VMs=".*"
            }
            @{
                Domain="."
                Username="Admin"
                Password='Pa$$w0rd'
                VMs=".*"
            }
            @{
                Domain="."
                Username="Administrator"
                Password='Pa55w.rd'
                VMs=".*"
            }
            @{
                Domain="."
                Username="Admin"
                Password='Pa55w.rd'
                VMs=".*"
            }
        )
    }

    shoutOut "Using these credentials..." Cyan
    shoutOut ($credentialEntries | ConvertTo-Json -Depth 2)

    $Credentials = $credentialEntries | % {
        if (!$_.Username -or !$_.Password) {
            return
        }

        $domain = if ($_.Domain) { $_.Domain } else { "." }
        $c = New-PSCredential ("{0}\{1}" -f $Domain,$_.UserName) $_.Password
        $_.Credential = $c
        return $c
    }

    $preRearmOps = @()
    $postRearmOps = @()

    if ($RearmVMsConfig = $Configuration["Rearm-VMs"]) {
        if ( ($p = $RearmVMsConfig["PreRearm"]) ) { $preRearmOps = $p }
        if ( ($p = $RearmVMsConfig["PostRearm"]) ) { $postRearmOps = $p } 
    }

    $VMs | % {
        
        $vm = $_
        
        $preRearmOps | ? { $_ } | % { Invoke-ShoutOut $_ }
        
        $arCreds = $credentialEntries | ? { $_.Credential -and ($vm.VMName -match $_.VMs) } | % { $_.Credential }
        $success = ActiveRearm-VM $vm $arCreds

        if (!$success) {
            $applicableEntries = $credentialEntries | ? { $_.Credential -and ($vm.VMName -match $_.VMs) }
            foreach ($entry in $applicableEntries) {
                $success = _passiveRearmVM $vm $entry
                if ($success) { break }
            }
        }
        
        if (!$success) {
            shoutOut "Failed to rearm '$($vm.VMName)'!" Red
            $notes = $vm.Notes
            $vm | Set-VM -Notes "REARM FAILED DURING SETUP, this machine may need to be rearmed manually.`n$notes"
        }

        $postRearmOps | ? { $_ } | % { Invoke-ShoutOut $_ }

    }

    shoutOut "VM Rearm check finished..." Green
}