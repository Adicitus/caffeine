
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

function _runOperations($registryKey, $registryValue="NextOperation", $Operations, $Conf, $Vars=@{}) {
    # Sanitize the input.
    $Operations = $Operations | Where-Object {
        $_ -ne $null
    }
    $shouldQuit = $false
    $shouldIncrement = $true

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
            exit
        }
    }

    $OperationN = Query-RegValue $registryKey $registryValue # Get the current index of the pointer.

    if ($null -eq $OperationN) {
        $OperationN = 0
        Set-Regvalue $registryKey $registryValue $OperationN | Out-Null
    }

    Set-Regvalue $registryKey $registryValue ($OperationN+1) | Out-Null # Increment the pointer.
    while ( $Operations -and ($o = @($Operations)[$OperationN]) ) {
        shoutOut "Operation #$OperationN... " cyan
        switch ($o) {
            "CAFRestart" {
                shoutOut "CAFRestart operation, Restarting host..."
                shutdown /r /t 3 | Out-Null
                $shouldQuit = $true
                $shouldIncrement = $false
            }
            "CAFForceInteractive" {

                shoutOut "CAFForceInteractive operation." Cyan
                shoutOut "Attempting to enter into an interactive user session." Cyan

                $r = _forceInteractive $conf
                
                if ($r.Repeat) {
                    Set-Regvalue $registryKey $registryValue $OperationN
                }

                if ($r.Success) {
                    "Broke into interactive session and finished running there." | shoutOut -MsgType Success
                    $shouldQuit = $true
                    $shouldIncrement = $false
                } else {
                    "Failed to enter into an interactive session!" | shoutOut -MsgType Error
                }

            }
            default {
                $o | Run-Operation -OutNull
            }
        }
        shoutOut "Operation #$OperationN done!" Green

        if ($shouldIncrement) {
            $OperationN = Query-RegValue $registryKey $registryValue # Get the current index of the pointer.
            Set-Regvalue $registryKey $registryValue ($OperationN+1) | Out-Null # Increment the pointer.
        }

        if ($shouldQuit) {
            shoutOut "Operations indicate that the script should quit."
            Break
        }

    }

    return $shouldQuit

}