# CAFfeinate the machine!

param(
    $JobFile = $null,
    [Switch]$SkipActiveVMRearm
)

. "$PSScriptRoot\Common\ShoutOut.ps1"
. "$PSScriptRoot\Common\Run-Operation.ps1"
. "$PSScriptRoot\Common\Parse-ConfigFile.ps1"
. "$PSScriptRoot\Common\Query-RegValue.ps1"
. "$PSScriptRoot\Common\Set-RegValue.ps1"
. "$PSScriptRoot\Common\Install-Feature.ps1"
. "$PSScriptRoot\Install-CAFRegistry.ps1"
. "$PSScriptRoot\Peel-PodFile.ps1"
. "$PSScriptRoot\Run-CAFSetup.ps1"

$script:_ShoutOutSettings.LogFile = "C:\CAFination.log"

$registryKey = "HKLM\SOFTWARE\CAFSetup"
shoutOut "Using registry key '$registryKey'..." cyan 

if (!$jobFile) {
    shoutOut "No job file specified, attempting to select one..." cyan -NoNewline
    $JobFile = "C:\setup\setup.ini"
    $f = Query-RegValue $registryKey "JobFile"
    if ($f) { $JobFile = $f }
    shoutOut " Using $JobFile..." Cyan
}

shoutOut "Parsing the job file..." Cyan
$conf = { Parse-ConfigFile $JobFile -NotStrict } | Run-Operation
if ($conf -isnot [hashtable]) {
    shoutOut "Unable to parse the job file @ '$JobFile'! Quitting!" Red
    return
}

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

$SetupRoot = Split-Path $JobFile

shoutOut "Done!" Green

Install-CAFRegistry $registryKey $conf ". '$PSCommandPath'"

$installSteps = @{}

$installSteps[0] = @{
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

        Set-RegValue $registryKey "InstallStep" 1 REG_DWORD
    }
}
$installSteps[1] = @{
    Name="FeaturesStep"
    Caption="Installing required features..."
    Block = {
        $conf.Features.Keys | % {
            ShoutOut " |-> '$_'" White
            Install-Feature $_
        }
        Set-RegValue $registryKey "InstallStep" 2 REG_DWORD
    }
}
$installSteps[2] = @{
    Name="PodsStep"
    Caption="Peeling pods..."
    Block = {
        $pods = ls -Recurse $SetupRoot | ? { $_ -match "\.(vhd(x)?|rar|exe)$" }
        
        foreach ($pod in $pods) {
            Peel-PodFile $pod
        }

        $loadHiveConfigs | Run-Operation # All pods have been peeled, ready to look for hives!

        Set-RegValue $registryKey "InstallStep" 3 REG_DWORD
    }
}
$installSteps[3] = @{
    Name="HyperVStep"
    Caption="Setting up Hyper-V environment..."
    Block = {
        
        if (Get-module Hyper-V -ListAvailable -ErrorAction SilentlyContinue) {
            
            Run-CAFSetup $conf -SkipActiveVMRearm:$SkipActiveVMRearm

        } else {
            shoutOut "Hyper-V is not installed, skipping..."
        }
        Set-RegValue $registryKey "InstallStep" 4 REG_DWORD
    }
}
$installSteps[4] = @{ # Mostly here to run operations when HyperVStep is done.
    Name="FinalizeStep"
    Caption="Finalizing setup..."
    Block = {
        
        Set-RegValue $registryKey "InstallStep" 5 REG_DWORD
    }
}
$installSteps[5] = @{ # This step will be repeated everytime the script is run.
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
        shoutOut "Done checking configuration"

        return $true # Signal 'stop'
    }
}



$stepN = Query-RegValue  $registryKey "InstallStep"

if ($stepN -gt 2)  { $loadHiveConfigs | Run-Operation } # All hives should have been set up, looking for configs!

while ($step = $installSteps[$stepN]){
    ShoutOut "Installation step: $stepN ($($step.Name))" cyan
    ShoutOut ("=" * 80) cyan
    
    shoutOut "Running operations..." Cyan
    
    
    $operations = $conf[$step.Name].Operation

    $OperationN = Query-RegValue $registryKey "NextOperation"
    Set-Regvalue $registryKey "NextOperation" ($OperationN+1)
    while ( $operations -and ($o = @($operations)[$OperationN]) ) {
        shoutOut "Operation #$OperationN... " cyan
        $o | Run-Operation | Out-Null
        shoutOut "Operation #$OperationN done!" Green

        $OperationN = Query-RegValue $registryKey "NextOperation"
        Set-Regvalue $registryKey "NextOperation" ($OperationN+1) 
    }

    shoutOut "$($step.caption)" magenta
    $Stop = . $step.block
    shoutOut "Step Block done!" Magenta
    Set-Regvalue $registryKey "NextOperation" 0 
    $stepN = Query-RegValue  $registryKey "InstallStep"
    if ($Stop -is [bool] -and $Stop) {
        break;
    }
}

shoutOut "Caffeination done!" Green

