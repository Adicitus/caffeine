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
            exit
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
                Restart-Computer -Force
                Start-Sleep -Seconds 5
                exit
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