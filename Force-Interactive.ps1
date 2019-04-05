function Force-Interactive{
    param(
        $conf,
        [string]$command = "$PSScriptRoot\caffeinate.ps1"
    )

    $ACGCoreDir = Get-Module ACGCore | % ModuleBase

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
        $sessionIDs = $ps | % { $_.SessionID } | Sort-Object -Unique

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
                    $r = & "$ACGCoreDir\bin\PSExec\PSExec.exe" "\\${env:COMPUTERNAME}" -u $u.Caption -p $cred.Password -i $sessionID -h -accepteula powershell -WindowStyle Max -Command . $command *>&1
                    shoutOut "Result:" Cyan
                    shoutOut "'$r'"

                    if ($r -match "Error Code 0") {
                        shoutOut "Success" Success
                        return $true
                    }
                }
            }
        }

        return $false
    }
}