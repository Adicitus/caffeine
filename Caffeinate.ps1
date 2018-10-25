<# CAFfeinate the machine!
.SYNOPSIS
This is the core script for the Caffeine setup method, it is used to manage
the flow of the setup process.

.DESCRIPTION
This is the core script for the Caffeine setup method, it is used to manage
the flow of the setup process.

.PARAMETER JobFile
The path to the job file to use for this setup. If this
parameter is not specified the the script will look for an appropriate
configuration file to use.

It starts by looking at the "JobFile" value under Under the  "HKLM\SOFTWARE\CAFSetup"
key in the registry, and if that fails it then tries to use "C:\setup\setup.ini".

The job file used by the script during it's first execution will will be used
to populate the "HKLM\SOFTWARE\CAFSetup\JobFile" registry value.

.PARAMETER ACGCoreDir
A directory where files of the ACGCore module can be found. Files in this directory
will be copied to the PSModulePath if not already on it.

.PARAMETER LogFile
Path to the log file where messages from this script should be written.

.PARAMETER SkipActiveRearm
Flag used to skip the costly process of trying to rearm any VMs included in the
setup. This flag is usually not used, since Run-CAFSetup should determine which
VMs need to be rearmed.
#>
param(
    $JobFile = $null,
    $ACGCoreDir="$PSScriptroot\Common",
    $LogFile = "C:\CAFination.log",
    [Switch]$SkipVMRearm
)

# =========================================================================== #
# ==================== Start: Bootstrapping the script ====================== #
# =========================================================================== #

$bootstrapLog = "{0}\bootstrap.{1:yyyyMMddhhmmss}.log" -f $PSScriptRoot,[datetime]::Now
"Starting Caffeination.ps1..." >> $bootstrapLog
"Starting Caffeine bootstrap..." >> $bootstrapLog

if (-not (Get-Module "ACGCore" -ListAvailable -ea SilentlyContinue)) {
    "ACGCore module not available, copying ACGCore files to PSModulePath..." >> $bootstrapLog
    Copy-Item $ACGCoreDir "C:\Windows\System32\WindowsPowerShell\v1.0\Modules\ACGCore" -Recurse *>&1 >> $bootstrapLog
}

"Importing ACGCore..." >> $bootstrapLog
Import-Module ACGCore  *>&1 >> $bootstrapLog
if (-not (Get-Module ACGCore)) {
    "Unable to import ACGCore module from PSModulePath!" >> $bootstrapLog
    "Attempting to import from the given ACGCoreDir..." >> $bootstrapLog
    Import-Module "$ACGCoreDir\ACGCore.psd1"
}

if (-not (Get-Command ShoutOut -ea SilentlyContinue)) {
    "Unable to find the 'shoutOut' command! Quitting!" >> $bootstrapLog
    return
} else {
    "'ShoutOut' is available, starting logging to '$LogFile'..." >> $bootstrapLog
}

"Caffeine bootstrap finished." >> $bootstrapLog

# =========================================================================== #
# ======================== Start: Main script body ========================== #
# =========================================================================== #

. "$PSScriptRoot\Install-CAFRegistry.ps1"
. "$PSScriptRoot\Peel-PodFile.ps1"
. "$PSScriptRoot\Verify-Assertions.ps1"
. "$PSScriptRoot\Run-CAFSetup.ps1"

$script:_ShoutOutSettings.LogFile = $LogFile

shoutOut "Starting caffeination..."

$registryKey = "HKLM\SOFTWARE\CAFSetup"
shoutOut "Using registry key '$registryKey'..." cyan 

# =========================================================================== #
# ==================== Start: Getting job configuration ===================== #
# =========================================================================== #

if (!$jobFile) {
    shoutOut "No job file specified, attempting to select one..." cyan -NoNewline
    $JobFile = "C:\setup\setup.ini"
    $f = Query-RegValue $registryKey "JobFile"
    if ($f) { $JobFile = $f }
    shoutOut " Using $JobFile..." Cyan
}

if (!(Test-Path $jobFile)) {
    shoutOut "Unable to find the job file '$JobFile'! Quitting" Red
    return
}

shoutOut "Parsing the job file..." Cyan
$conf = { Parse-ConfigFile $JobFile -NotStrict } | Run-Operation
if ($conf -isnot [hashtable]) {
    shoutOut "Unable to parse the job file @ '$JobFile'! Quitting!" Red
    return
}

$SetupRoot = Split-Path $JobFile

shoutOut "Done!" Green

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

Install-CAFRegistry $registryKey $conf ". '$PSCommandPath'" $JobFile $SetupRoot

$stepN = Query-RegValue  $registryKey "InstallStep"

if ($stepN -gt 2)  { $loadHiveConfigs | Run-Operation } # All hives should have been set up after step 2, looking for configs!

# =========================================================================== #
# ==================== Start: Defining setup-sequence ======================= #
# =========================================================================== #

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
            { Install-Feature $_ } | Run-Operation
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
            
            Run-CAFSetup $conf -SkipVMRearm:$SkipVMRearm

        } else {
            shoutOut "Hyper-V is not installed, skipping..."
        }
        Set-RegValue $registryKey "InstallStep" 4 REG_DWORD
    }
}
# Mostly here to run operations when HyperVStep is done.
# Operations in the Finalize step can, for example, be used to
# install software or perform post-import configuration on VMs.
$installSteps[4] = @{
    Name="FinalizeStep"
    Caption="Finalizing setup..."
    Block = {
        Set-RegValue $registryKey "InstallStep" 5 REG_DWORD
    }
}
$installSteps[5] = @{
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
        Set-RegValue $registryKey "InstallStep" 6 REG_DWORD
    }
}
$installSteps[6] = @{
    Name="VerifyStep"
    Caption="Checking if all assertions about the current setup are satisfied..."
    Block={
        Verify-Assertions $conf
        Set-RegValue $registryKey "InstallStep" 7 REG_DWORD
    }
}
$installSteps[7] = @{ # This step will be repeated everytime the script is run.
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

# =========================================================================== #
# ======================= Start: Setup-Sequence loop ======================== #
# =========================================================================== #

<#
.SYNOPSIS
Helper function, runs operations.

.DESCRIPTION
Helper function to run operations specified in the job file, using a registry
value to keep track of the next operation in the sequence of operations. This
gives the operations the freedom to restart the computer, and the system will
pick up from the next operation once it reboots.

Operations are expected to appear in the same order that they should be
executed, and the function will not try to reorder them in any way.

.PARAMETER regsitryKey
The registry key under which to to store information.

.PARAMETER registryValue
Registry value under $RegistryKey to store the index of the next operation in.

.PARAMETER Operations
An array of operations to be executed, these can be either string expressions or script blocks.

.PARAMETER Conf
The configuration object, passed in to make it accessible to operations that might need it.

.PARAMETER Vars
Object passed in to record variables between calls to RunOperations. Must be retained and provided
by the caller.

.NOTES
This function is intended to allow the inclusion of more operation-like
declarations in job files, like: "Pre" as an alias and new name for "Operation"
(Operations executed before the step-block) and "Post" for operations that should be executed
after the step-block.

Additionally it may be a good idea to introduce Pre and Post hooks to [Global], that will be
executed prior to and after the main loop.

[20171111, JO] Pre and Post operation index should not be tracked across restarts, but rather they
should all be run each time the script runs. This is to keep the complexity of the system down, and
to allow declarations like [Global].Pre and [Global].Post to be used to "prime" the system each
time the script is run (for example by prepopulating the $conf variable with dynamic values in
[Global].Pre).

So this function won't be used outside of caffeinate.ps1 for the forseeable future.
#>
function runOperations($registryKey, $registryValue="NextOperation", $Operations, $Conf, $Vars=@{}) {
    $Operations = $Operations |? { $_ -ne $null } # Sanitize the input.
    
    function GetNextOperationNumber() {
        return Query-RegValue $registryKey $registryValue 
    }

    function RestartAndRepeat {
        param(
            [switch]$NoRestart
        )
        $n = GetNextOperationNumber
        shoutOut "Setting operation number to '$n'..."
        Set-RegValue $registryKey $registryValue ($n-1)
        if (!$NoRestart) {
            shoutOut "Restarting computer..."
            { shutdown /r /t 0 } | Run-Operation -OutNull
            pause
        }
    }

    $OperationN = Query-RegValue $registryKey $registryValue # Get the current index of the pointer.

    if ($OperationN -eq $null) {
        $OperationN = 0
        Set-Regvalue $registryKey $registryValue $OperationN
    }

    Set-Regvalue $registryKey $registryValue ($OperationN+1) # Increment the pointer.
    while ( $Operations -and ($o = @($Operations)[$OperationN]) ) {
        shoutOut "Operation #$OperationN... " cyan
        switch ($o) {
            "CAFRestart" {
                shoutOut "CAFRestart operation, Restarting host..."
                { shutdown /r /t 0 } | Run-Operation -OutNull
                pause
            }
            "CAFForceInteractive" {
                shoutOut "CAFForceInteractive operation." Cyan
                shoutOut "Attempting to enter into an interactive user session." Cyan

                if ([Environment]::UserInteractive) {
                    shoutOut "Already in an interactive session." Cyan
                    continue
                }

                $credentials = $conf.Keys | ? { $_ -match "^Credential" } | % { $conf[$_] }
                shoutOut "Found these credentials:" Cyan
                shoutOut $credentials

                shoutOut "Looking for logged on users..." Cyan
                do {
                    $interactiveSessions = gwmi -query "Select __PATH From Win32_LogonSession WHERE LogonType=2 OR LogonType=10 OR LogonType=11 OR LogonType=12 OR LogonType=13"
                    $users = $interactiveSessions | % { gwmi -query "ASSOCIATORS OF {$($_.__PATH)} WHERE ResultClass=Win32_UserAccount" }
                    # We're only interested in users whose credential are available.
                    $users = $users | ? {
                        $u = $_
                        $credentials | ? {
                            $r = $_.Username -eq $u.Name
                            if ($_.Domain -and ($_.Domain -ne ".")) {
                                $r = $r -and ($u.Domain -eq $_.Domain)
                            } else {
                                $r = $r -and ($u.Domain -eq $Env:COMPUTERNAME)
                            }
                            $r
                        }
                    }
                } while($users -eq $null)
                
                shoutOut "Found these users:" Cyan
                shoutOut $users


                foreach ( $u in @($users)) {
                    $ss = gwmi -query "ASSOCIATORS OF {$($u.__PATH)} Where ResultClass=Win32_LogonSession" | ? { $_.LogonType -in 2,10,11,12,13 }
                    $ps = $ss | % { gwmi -query "ASSOCIATORS OF {$($_.__PATH)} where ResultClass=Win32_Process" }
                    $sessionIDs = $ps | % { $_.SessionID } | sort -Unique

                    foreach($cred in @($credentials)) {
                        $k = if ((-not $cred.Domain) -or ($cred.Domain -eq ".")) {
                                "${env:COMPUTERNAME}\$($cred.Username)"
                            } else {
                                "$($cred.Domain)\$($cred.Username)"
                            }
                        if ($u.Caption -eq $k) {
                            shoutOut "Trying these credentials:" Cyan
                            shoutOut $cred
                            # Just in case we find more than one session ID for a user:
                            foreach ($sessionID in @($sessionIDs)) {
                                $r = & "$ACGCoreDir\bin\PSExec\PSExec.exe" "\\${env:COMPUTERNAME}" -u $u.Caption -p $cred.Password -i $sessionID -h -accepteula powershell -WindowStyle Max -Command . $PSCommandPath *>&1
                                shoutOut "Result:" Cyan
                                shoutOut "'$r'"

                                if ($r -match "Error Code 0") {
                                    shoutOut "Broke into interactive session and finished running there." Cyan
                                    shoutOut "Caffeine finished, exiting non-interactive mode."
                                    exit
                                }
                            }
                        }
                    }
                }
            }
            default {
                $o | Run-Operation -OutNull
            }
        }
        shoutOut "Operation #$OperationN done!" Green

        $OperationN = Query-RegValue $registryKey $registryValue # Get the current index of the pointer.
        Set-Regvalue $registryKey $registryValue ($OperationN+1) # Increment the pointer.
    }
}

$OperationVars = @{}

shoutOut "Running pre-setup operations..." Cyan
$operations = $conf["Global"].Pre
Set-Regvalue $registryKey "NextOperation.Global" 0
runOperations $registryKey "NextOperation.Global" $operations $conf $OperationVars

shoutOut "Starting setup-sequence..." magenta
while ($step = $installSteps[$stepN]){
    ShoutOut "Installation step: $stepN ($($step.Name))" cyan
    ShoutOut ("=" * 80) cyan
    
    shoutOut "Running PRE operations..." Cyan
    $operations = "Operation", "Pre" | % { $conf[$step.Name].$_ }
    runOperations $registryKey "NextOperation" $operations $conf $OperationVars

    $blockIsFinished = Query-Regvalue $registryKey "BlockIsFinished"
    if (-not $blockIsFinished) {
        shoutOut "Executing step block: $($step.caption)" magenta
        $Stop = . $step.block
        shoutOut "Step Block done!" Magenta
        Set-Regvalue $registryKey "BlockIsFinished" 1
    }

    shoutOut "Running POST operations..." Cyan
    $operations = $conf[$step.Name].Post
    runOperations $registryKey "NextPostOperation" $operations $conf $OperationVars

    Set-Regvalue $registryKey "NextOperation" 0
    Set-Regvalue $registryKey "NextPostOperation" 0
    Set-Regvalue $registryKey "BlockIsFinished" 0
    $stepN = Query-RegValue  $registryKey "InstallStep"
    if ($Stop -is [bool] -and $Stop) {
        break;
    }
}
shoutOut "Setup-sequence ended." magenta

shoutOut "Running post-setup operations..." Cyan
$operations = $conf["Global"].Post
Set-Regvalue $registryKey "NextOperation.Global" 0
runOperations $registryKey "NextOperation.Global" $operations $conf $OperationVars

shoutOut "Caffeination done!" Green

