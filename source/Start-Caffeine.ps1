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

.PARAMETER LogDir
Path to the directory where log files will be kept.
#>

function Start-Caffeine {
    param(
        $JobFile = $null,
        $LogDir = "C:\CaffeineLogs"
    )

    # =================================================================================== #
    # ============================ Start: Main script body ============================== #
    # =================================================================================== #

    $i = whoami.exe
    $d, $u = $i.split("\")
    $a = if ($u) {
        "{0}@{1}" -f $u, $d
    } else {
        $d
    }
    $LogFile = "{0}\run.{1:yyyyMMdd-HHmmss}.{2}.{3}.log" -f $logDir, [datetime]::now, $a, $PID

    Set-ShoutOutConfig -LogFile $LogFile

    shoutOut "Starting caffeination..."

    _verifyHives

    $registryKey = "HKLM\SOFTWARE\CAFSetup"
    shoutOut "Using registry key '$registryKey'..." 

    # =========================================================================== #
    # ==================== Start: Getting job configuration ===================== #
    # =========================================================================== #

    if (!$jobFile) {
        shoutOut "No job file specified, attempting to select one..." -NoNewline
        $JobFile = "C:\setup\setup.ini"
        $f = Query-RegValue $registryKey "JobFile"
        if ($f) { $JobFile = $f }
        shoutOut " Using $JobFile..."
    }

    if (!(Test-Path $jobFile)) {
        shoutOut "Unable to find the job file '$JobFile'! Quitting" Error
        return
    }

    shoutOut "Parsing the job file..."
    $conf = { Parse-ConfigFile $JobFile -NotStrict } | Invoke-ShoutOut
    if ($conf -isnot [hashtable]) {
        shoutOut "Unable to parse the job file @ '$JobFile'! Quitting!" Error
        return
    }

    shoutOut "Done!" Success

    # =========================================================================== #
    # ===================== End: Getting job configuration ====================== #
    # =========================================================================== #

    # =========================================================================== #
    # ==================== Start: Defining setup-sequence ======================= #
    # =========================================================================== #

    $tsf = $conf.Global.TaskSequenceFile | Select-Object -Last 1
    
    if ($null -eq $tsf) {
        throw "No task sequnce file specified in the configuration (should be defined as TaskSequenceFile declaration in the Global section)"
    }

    if ($tsf -isnot [string]) {
        $msg = "Invalid value for TaskSequenceFile specified. Expected a String, found '{0}' ({1})." -f $tsf.GetType().Name, $tsf
        throw $msg
    }

    if (-not (Test-Path $tsf -PathType Leaf)) {
        $msg = "TaskSequenceFile not found. Expected it to be @ '{0}'." -f $tsf
        throw $msg
    }

    "Using task sequence defined in '{0}'..." -f $tsf | shoutOut
    $installSteps = New-Object System.Collections.ArrayList
    $n = 0
    . $tsf | Where-Object { 
        $_ -is [hashtable]
    } | ForEach-Object {
        "Registering step '{0}' ('{1}') as step {2}..." -f $_.Name, $_.caption, $n++ | shoutOut
        $installSteps.add($_) | Out-Null
    }

    # =========================================================================== #
    # ===================== End: Defining setup-sequence ======================== #
    # =========================================================================== #

    # =========================================================================== #
    # ======================= Start: Setup-Sequence loop ======================== #
    # =========================================================================== #

    $stepN = Query-RegValue  $registryKey "InstallStep"
    $OperationVars = @{}

    shoutOut "Running pre-setup operations..."
    $operations = $conf["Global"].Pre
    Set-Regvalue $registryKey "NextOperation.Global" 0
    _runOperations $registryKey "NextOperation.Global" $operations $conf $OperationVars | Out-Null

    shoutOut "Starting setup-sequence..."
    while ($step = $installSteps[$stepN]){
        ShoutOut "Installation step: $stepN ($($step.Name))"
        ShoutOut ("=" * 80)
        
        $blockIsFinished = Query-Regvalue $registryKey "BlockIsFinished"
        
        if (-not $blockIsFinished) {
            shoutOut "Running PRE operations..."
            $operations = "Pre", "Operation" | ForEach-Object { $conf[$step.Name].$_ }
            $shouldQuit = _runOperations $registryKey "NextOperation" $operations $conf $OperationVars
            '$shouldQuit is: ' -f  $shouldQuit | shoutOut
            if ($shouldQuit) {
                "Quitting setup because _runOperations signaled we should." | shoutOut
                return
            }
            
            shoutOut "Executing step block: $($step.caption)"
            $Stop = . $step.block
            shoutOut "Step Block done!"
            Set-Regvalue $registryKey "BlockIsFinished" 1
            Set-Regvalue $registryKey "NextOperation" 0
        }

        shoutOut "Running POST operations..."
        $operations = $conf[$step.Name].Post
        $shouldQuit = _runOperations $registryKey "NextOperation" $operations $conf $OperationVars
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
    shoutOut "Setup-sequence ended."

    shoutOut "Running post-setup operations..."
    $operations = $conf["Global"].Post
    Set-Regvalue $registryKey "NextOperation.Global" 0
    _runOperations $registryKey "NextOperation.Global" $operations $conf $OperationVars

    # =========================================================================== #
    # ======================== End: Setup-Sequence loop ========================= #
    # =========================================================================== #

    shoutOut "Caffeination done!" Success

    # =================================================================================== #
    # ============================= End: Main script body =============================== #
    # =================================================================================== #
}