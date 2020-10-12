<# CAFfeinate the machine!
.SYNOPSIS
This is the core command for the Caffeine setup method, it is used to manage the flow of the setup process.

.DESCRIPTION
This is the core command for the Caffeine setup method, it is used to manage the flow of the setup process.

.PARAMETER JobFile
The path to the job file to use for this setup. If this
parameter is not specified the the script will look for an appropriate
configuration file to use.

It starts by looking at the "JobFile" value under Under the  "HKLM\SOFTWARE\CAFSetup"
key in the registry, and if that fails it then tries to use "C:\setup\setup.ini".

The job file used by the script during it's first execution will will be used
to populate the "HKLM\SOFTWARE\CAFSetup\JobFile" registry value.

.PARAMETER LogFile
Path to the log file where messages from this script should be written.

.PARAMETER SkipActiveRearm
Flag used to skip the costly process of trying to rearm any VMs included in the
setup. This flag is usually not used, since Run-CAFSetup should determine which
VMs need to be rearmed.
#>

function Start-Caffeine {
    param(
        $JobFile = $null,
        $LogFile = "C:\CAFination.log",
        [Switch]$SkipVMRearm
    )

    # =========================================================================== #
    # ======================== Start: Main script body ========================== #
    # =========================================================================== #

    Set-ShoutOutConfig -LogFile $LogFile

    shoutOut "Starting caffeination..."

    _verifyHives

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

    # =========================================================================== #
    # ===================== End: Getting job configuration ====================== #
    # =========================================================================== #

    _installCAFRegistry $registryKey $conf ". '$PSCommandPath'" $JobFile $SetupRoot

    $stepN = Query-RegValue  $registryKey "InstallStep"

    # =========================================================================== #
    # ==================== Start: Defining setup-sequence ======================= #
    # =========================================================================== #

    $tsf = $conf.Global.TaskSequenceFile | Select-Object -Last 1
    if (!($tsf -is [string] -and (Test-Path $tsf))) {
        $tsf = "$PSScriptRoot\.assets\default.ts\default.ts.ps1"
    }
    "Using task sequence defined in '{0}'..." -f $tsf | shoutOut -Foreground Cyan
    $installSteps = New-Object System.Collections.ArrayList
    $n = 0
    . $tsf | ? { 
        $_ -is [hashtable]
    } | % {
        "Registering step '{0}' ('{1}') as step {2}..." -f $_.Name, $_.caption, $n++ | shoutOut
        $installSteps.add($_) | Out-Null
    }

    # =========================================================================== #
    # ===================== End: Defining setup-sequence ======================== #
    # =========================================================================== #

    # =========================================================================== #
    # ======================= Start: Setup-Sequence loop ======================== #
    # =========================================================================== #

    . "$PSScriptRoot\_runOperations.ps1"

    $OperationVars = @{}

    shoutOut "Running pre-setup operations..." Cyan
    $operations = $conf["Global"].Pre
    Set-Regvalue $registryKey "NextOperation.Global" 0
    _runOperations $registryKey "NextOperation.Global" $operations $conf $OperationVars | Out-Null

    shoutOut "Starting setup-sequence..." Magenta
    while ($step = $installSteps[$stepN]){
        ShoutOut "Installation step: $stepN ($($step.Name))" cyan
        ShoutOut ("=" * 80) cyan
        
        shoutOut "Running PRE operations..." Cyan
        $operations = "Pre", "Operation" | % { $conf[$step.Name].$_ }
        $shouldQuit = _runOperations $registryKey "NextOperation" $operations $conf $OperationVars
        shoutOut $shouldQuit
        if ($shouldQuit) {
            "Quitting setup because _runOperations signaled we should." | shoutOut
            return
        }

        $blockIsFinished = Query-Regvalue $registryKey "BlockIsFinished"
        if (-not $blockIsFinished) {
            shoutOut "Executing step block: $($step.caption)" magenta
            $Stop = . $step.block
            shoutOut "Step Block done!" Magenta
            Set-Regvalue $registryKey "BlockIsFinished" 1
        }

        shoutOut "Running POST operations..." Cyan
        $operations = $conf[$step.Name].Post
        $shouldQuit = _runOperations $registryKey "NextPostOperation" $operations $conf $OperationVars
        shoutOut $shouldQuit
        if ($shouldQuit) { 
            "Quitting setup because _runOperations signaled we should." | shoutOut
            return
        }

        Set-Regvalue $registryKey "NextOperation" 0
        Set-Regvalue $registryKey "NextPostOperation" 0
        Set-Regvalue $registryKey "BlockIsFinished" 0
        if ($Stop -is [bool] -and $Stop) {
            break;
        }
        $stepN += 1
        Set-RegValue $registryKey "InstallStep" $stepN
    }
    shoutOut "Setup-sequence ended." magenta

    shoutOut "Running post-setup operations..." Cyan
    $operations = $conf["Global"].Post
    Set-Regvalue $registryKey "NextOperation.Global" 0
    _runOperations $registryKey "NextOperation.Global" $operations $conf $OperationVars

    # =========================================================================== #
    # ======================== End: Setup-Sequence loop ========================= #
    # =========================================================================== #

    shoutOut "Caffeination done!" Green

    # =========================================================================== #
    # ========================= End: Main script body =========================== #
    # =========================================================================== #
}