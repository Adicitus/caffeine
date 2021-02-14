function _forceInteractive{
    param(
        $conf,
        [string]$command = "Start-Caffeine"
    )

    if ([Environment]::UserInteractive) {
        shoutOut "Already in an interactive session."
        return @{ Success = $false; Repeat = $false }
    }

    $credentials = $conf.Keys | Where-Object {
        $_ -match "^Credential"
    } | ForEach-Object {
        $conf[$_]
    }
    shoutOut "Found these credentials:"
    shoutOut $credentials


    $waitLimit = [timespan]::FromMinutes(2)
    $waitStart = [datetime]::Now
    shoutOut "Looking for logged on users..."
    do {
        $interactiveSessions = Get-WmiObject -query "Select __PATH From Win32_LogonSession WHERE LogonType=2 OR LogonType=10 OR LogonType=11 OR LogonType=12 OR LogonType=13"
        $users = $interactiveSessions | ForEach-Object {
            Get-WmiObject -query "ASSOCIATORS OF {$($_.__PATH)} WHERE ResultClass=Win32_UserAccount"
        }
        # We're only interested in users whose credential are available.
        $users = $users | Where-Object {
            $u = $_
            $credentials | Where-Object {
                $r = $_.Username -eq $u.Name
                if ($_.Domain -and ($_.Domain -ne ".")) {
                    $r = $r -and ($u.Domain -eq $_.Domain)
                } else {
                    $r = $r -and ($u.Domain -eq $Env:COMPUTERNAME)
                }
                $r
            }
        }

        $duration = [datetime]::Now - $waitStart

        if ($duration -gt $waitLimit) {
            "Unable to find an active session to break into, trying to reset autologin and restarting." | shoutOut
            $nextInstallStep = Query-RegValue HKLM\SOFTWARE\CAFSetup InstallStep
            Set-RegValue HKLM\SOFTWARE\CAFSetup InstallStep ($nextInstallStep - 1)
            if (!(Test-Path C:\Temp -PathType Container)) { mkdir C:\temp }
            _ensureAutoLogon $conf "C:\temp"
            Restart-Computer
            return @{ Success = $false; Repeat = $true }
        }
    } while($null -eq $users)
    
    shoutOut "Found these users:"
    shoutOut $users

    
    foreach ( $u in @($users)) {
        $ss = Get-WmiObject -query "ASSOCIATORS OF {$($u.__PATH)} Where ResultClass=Win32_LogonSession" | Where-Object { $_.LogonType -in 2,10,11,12,13 }
        $ps = $ss | ForEach-Object { Get-WmiObject -query "ASSOCIATORS OF {$($_.__PATH)} where ResultClass=Win32_Process" }
        $sessionIDs = $ps | ForEach-Object { $_.SessionID } | Sort-Object -Unique

        foreach($cred in @($credentials)) {
            $k = if ((-not $cred.Domain) -or ($cred.Domain -eq ".")) {
                    "${env:COMPUTERNAME}\$($cred.Username)"
                } else {
                    "$($cred.Domain)\$($cred.Username)"
                }
            if ($u.Caption -eq $k) {
                shoutOut "Trying these credentials:"
                shoutOut $cred
                # Just in case we find more than one session ID for a user:
                foreach ($sessionID in @($sessionIDs)) {
                    $r = & "$PSScriptRoot\.assets\PSExec\PSExec.exe" "\\${env:COMPUTERNAME}" -u $u.Caption -p $cred.Password -i $sessionID -h -accepteula powershell -WindowStyle Max -Command . $command *>&1
                    shoutOut "Result:"
                    shoutOut "'$r'"

                    if ($r -match "Error Code 0") {
                        shoutOut "Success" Success
                        return @{ Success = $true; Repeat = $false }
                    }
                }
            }
        }

        return @{ Success = $false; Repeat = $false }
    }
}