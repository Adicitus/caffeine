
. "$PSScriptRoot\Peel-PodFile.ps1"
. "$PSScriptRoot\Verify-Assertions.ps1"
. "$PSScriptRoot\Run-CAFSetup.ps1"

# TODO: This should be a helper function
$loadHiveConfigs = { # Closure to update the configuration with hive configurations
    
    Get-Volume | ? { $VolumePath = Find-VolumePath $_ -FirstOnly; $volumePath } | % { # Rewrite to use Win32_MountPoint instead of Driveletter
        $hiveConfig = "{0}hive.ini" -f $VolumePath
        write-host $hiveConfig
        if (Test-Path $hiveConfig) {
            shoutOut "Found hive config @ $hiveConfig, checking validity..." -NoNewline
            try {
                Parse-ConfigFile $hiveConfig | Out-Null # Assuming we are using a strict parser.
                shoutOut "Ok!" Green
                shoutOut "Including hive config @ '$hiveConfig'..." Cyan
                { Parse-ConfigFile $hiveConfig -NotStrict -Config $conf } | Run-Operation |Out-Null
            } catch {
                shoutOut "Invalid config file!" Red
                shoutOUt "'$_'"
            }
        }
    }
}

if ($stepN -gt 2)  { $loadHiveConfigs | Run-Operation } # All hives should have been set up after step 2, looking for configs!

@{
    Name="InitializationStep"
    Caption="Initializing the host environment..."
    Block={
        $r = { Test-Path $JobFile } | Run-Operation
        if (!$r -or $r -is [System.Management.Automation.ErrorRecord]) {
            shoutOut "The specified job file is missing! ('$JobFile')"
        }
        $r = { Get-NetAdapter | ? { $_.Status -eq "Up" } } | Run-Operation
        if (!$r -or $r -is [System.Management.Automation.ErrorRecord]) {
            shoutOut "There seems to be no active network adapters on this system!" Yellow
        }
    }
}
@{
    Name="FeaturesStep"
    Caption="Installing required features..."
    Block = {
        $conf.Features.Keys | % {
            ShoutOut " |-> '$_'" White
            { Install-Feature $_ } | Run-Operation
        }
    }
}
@{
    Name="PodsStep"
    Caption="Peeling pods..."
    Block = {
        $pods = ls -Recurse $SetupRoot | ? { $_ -match "\.(vhd(x)?|rar|exe)$" }
        
        foreach ($pod in $pods) {
            Peel-PodFile $pod
        }

        $loadHiveConfigs | Run-Operation # All pods have been peeled, ready to look for hives!
    }
}
@{
    Name="HyperVStep"
    Caption="Setting up Hyper-V environment..."
    Block = {
        
        if (Get-module Hyper-V -ListAvailable -ErrorAction SilentlyContinue) {
            
            Run-CAFSetup $conf -SkipVMRearm:$SkipVMRearm

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
            Run-Operation { (New-Object -Com Shell.Application).NameSpace('shell:::{4234d49b-0245-4df3-b780-3893943456e1}').Items() | % { $_.Name } }
            . "$PSSCriptRoot\Common\Pin-App.ps1"
            if ($conf.Taskbar.ContainsKey("Pin")) {
                $conf.Taskbar.Pin | ? { $_ -is [string] } | % { shoutOUt "Pinning '$_'"; $_ } | % { Pin-App $_ }
            }
            if ($conf.Taskbar.ContainsKey("Unpin")) {
                $conf.Taskbar.Unpin | ? { $_ -is [string] } | % { shoutOUt "Unpinning '$_'"; $_ } | % { Pin-App $_ -Unpin }
            }
        }
    }
}
@{
    Name="VerifyStep"
    Caption="Checking if all assertions about the current setup are satisfied..."
    Block={
        Verify-Assertions $conf
    }
}
@{ # This step will be repeated everytime the script is run.
    Name="WatchdogStep"
    Caption="Checking environment..."
    Block = {
        
        shoutOut "WinRM state:"
        {sc.exe queryex winrm} | Run-Operation -OutNull
        shoutOut "Checking WinRM Configuration... " Cyan
        $winrmConfig = { sc.exe qc winrm } | Run-Operation
        if (!($winrmConfig | ? { $_ -match "START_TYPE\s+:\s+2"})) { # 2=Autostart
            { sc.exe config winrmstart= auto } | Run-Operation -OutNull
        }

        { sc.exe failure winrm reset= 84600 command= "winrm quickconfig -q -force" actions= restart/2000/run/5000 } | Run-Operation -OutNull


        shoutOut "Done checking configuration"

        return $true # Signal 'stop'
    }
}