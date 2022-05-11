
#requires -Modules ACGCore

. "$PSScriptRoot\_peelPodFile.ps1"
. "$PSScriptRoot\_verifyAssertions.ps1"
. "$PSScriptRoot\_runCAFSetup.ps1"

# TODO: This should be a helper function
$loadHiveConfigs = { # Closure to update the configuration with hive configurations
    
    Get-Volume | Where-Object {
        $VolumePath = Find-VolumePath $_ -FirstOnly
        $volumePath
    } | ForEach-Object { # Rewrite to use Win32_MountPoint instead of Driveletter
        $hiveConfig = "{0}hive.ini" -f $VolumePath
        write-host $hiveConfig
        if (Test-Path $hiveConfig) {
            shoutOut "Found hive config @ $hiveConfig, checking validity..." -NoNewline
            try {
                Parse-ConfigFile $hiveConfig | Out-Null # Assuming we are using a strict parser.
                shoutOut "Ok!" Green
                shoutOut "Including hive config @ '$hiveConfig'..." Cyan
                { Parse-ConfigFile $hiveConfig -NotStrict -Config $conf } | Invoke-ShoutOut |Out-Null
            } catch {
                shoutOut "Invalid config file!" Red
                shoutOUt "'$_'"
            }
        }
    }
}

if ($stepN -gt 2)  { $loadHiveConfigs | Invoke-ShoutOut } # All hives should have been set up after step 2, looking for configs!

@{
    Name="InitializationStep"
    Caption="Initializing the host environment..."
    Block={
        $r = { Test-Path $JobFile } | Invoke-ShoutOut
        if (!$r -or $r -is [System.Management.Automation.ErrorRecord]) {
            shoutOut "The specified job file is missing! ('$JobFile')"
        }
        $r = { Get-NetAdapter | Where-Object { $_.Status -eq "Up" } } | Invoke-ShoutOut
        if (!$r -or $r -is [System.Management.Automation.ErrorRecord]) {
            shoutOut "There seems to be no active network adapters on this system!" Yellow
        }
    }
}
@{
    Name="FeaturesStep"
    Caption="Installing required features..."
    Block = {
        $conf.Features.Keys | ForEach-Object {
            ShoutOut " |-> '$_'" White
            { Install-Feature $_ } | Invoke-ShoutOut
        }
    }
}
@{
    Name="PodsStep"
    Caption="Peeling pods..."
    Block = {
        $SetupRoot = Split-Path $JobFile
        $pods = Get-ChildItem -Recurse $SetupRoot | Where-Object { $_ -match "\.(vhd(x)?|rar|exe)$" }
        
        foreach ($pod in $pods) {
            _peelPodFile $pod
        }

        $loadHiveConfigs | Invoke-ShoutOut # All pods have been peeled, ready to look for hives!
    }
}
@{
    Name="HyperVStep"
    Caption="Setting up Hyper-V environment..."
    Block = {
        
        if (Get-module Hyper-V -ListAvailable -ErrorAction SilentlyContinue) {
            
            _runCAFSetup $conf -SkipVMRearm:$SkipVMRearm

        } else {
            shoutOut "Hyper-V is not installed, skipping..."
        }
    }
}
# Mostly here to run operations when HyperVStep is done.
# Operations in the Finalize step can, for example, be used to
# install software or perform post-import configuration on VMs.
@{
    Name="FinalizeStep"
    Caption="Finalizing setup..."
    Block = {
        
    }
}
@{
    Name="CustomizeStep"
    Caption="Customizing account... (ie: pinning apps)"
    Block = {
        if ($conf.ContainsKey("Taskbar")) {
            if ( !(Get-Process explorer -ea SilentlyContinue) ) {
                shoutOut "Starting explorer..."
                Start-Process explorer
            }
            shoutOut "Modifying the taskbar..."
            shoutOut "Available apps:"
            Invoke-ShoutOut { (New-Object -Com Shell.Application).NameSpace('shell:::{4234d49b-0245-4df3-b780-3893943456e1}').Items() | ForEach-Object { $_.Name } }
            
            if ($conf.Taskbar.ContainsKey("Pin")) {
                $conf.Taskbar.Pin | Where-Object {
                    $_ -is [string]
                } | ForEach-Object {
                    shoutOUt "Pinning '$_'"
                    Pin-App $_
                }
            }
            if ($conf.Taskbar.ContainsKey("Unpin")) {
                $conf.Taskbar.Unpin | Where-Object {
                    $_ -is [string]
                } | ForEach-Object {
                    shoutOUt "Unpinning '$_'"
                    Pin-App $_ -Unpin
                }
            }
        }
    }
}
@{
    Name="VerifyStep"
    Caption="Checking if all assertions about the current setup are satisfied..."
    Block={
        _verifyAssertions $conf
    }
}
@{ # This step will be repeated everytime the script is run.
    Name="WatchdogStep"
    Caption="Checking environment..."
    Block = {
        
        shoutOut "WinRM state:"
        {sc.exe queryex winrm} | Invoke-ShoutOut -OutNull
        shoutOut "Checking WinRM Configuration... " Cyan
        $winrmConfig = { sc.exe qc winrm } | Invoke-ShoutOut
        if  ( -not (
                    $winrmConfig | Where-Object {
                        $_ -match "START_TYPE\s+:\s+2"
                    }
            )
        ) { # 2=Autostart
            { sc.exe config winrmstart= auto } | Invoke-ShoutOut -OutNull
        }

        { sc.exe failure winrm reset= 84600 command= "winrm quickconfig -q -force" actions= restart/2000/run/5000 } | Invoke-ShoutOut -OutNull


        shoutOut "Done checking configuration"

        return $true # Signal 'stop'
    }
}