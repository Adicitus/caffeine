# _verifyHives.ps1
<#
.SYNOPSIS
!WIP! Checks whether all installed hives have been mounted, and attempts to
mount any that have not been so.
.NOTES
This function assumes that all hives are installed using the ScheduledJob
method and the MountHive(<vhdname>) naming scheme. This is written with
Install-Hive from commit 393464c3cc4bf28d022785f0ec4adb217cffdfa5 of ACGCore
in mind.

This function should be rewritten to use a more robust HiveDisk API once it is in place.
#>
function _verifyHives {
    param()

    trap {
        shoutOut "Error occured in _verifyHives!" Error
        shoutOut $_
    }

    shoutOut "Verifying that all installed hives have been mounted..."

    $userDirs = ls "C:\Users"

    $userDirs | % {
        $path = "{0}\AppData\Local\Microsoft\Windows\PowerShell\ScheduledJobs" -f $_.FullName
        if ((Test-Path $path)) {
            "Found a ScheduledJobs directory under '{0}'." -f $_.Name | ShoutOut
            "Collecting ScheduledJobs..." | ShoutOut
            ls $path | %  {
                "Found '{0}'." -f $_.Name | ShoutOut
                @{ Name=$_.Name; Path= $path }
            }
        }
    } | ? {
        $_.Name -match "^MountHive\((?<hivename>.+)\)$"
    } | % {
        "Loading '{0}'..." -f $_.Name | ShoutOut
        $def = [Microsoft.PowerShell.ScheduledJob.ScheduledJobDefinition]::LoadFromStore($_.Name, $_.Path)
        $vhdPath = $def.InvocationInfo.Parameters[0] | ? { $_.Name -eq "ArgumentList" } | % Value | Select -First 1
        "VHD located @ '{0}'." -f $vhdPath | shoutOut

        if ($vhd = Get-VHD $vhdPath -ErrorAction SilentlyContinue) {
            "VHD is accessible." | shoutOut
            if (!$vhd.Attached) {
                "VHD is not mounted, attempting to mount it..." | shoutOUt
                { $def.Run() } | Run-Operation
            } else {
                "VHD seems to be mounted as disk number {0}." -f $vhd.Number | ShoutOut
            }
        } else {
            "VHD is inaccessible." | shoutOut -MsgType Error
        }
    }

    shoutOut "Finished verifying the hives."
    
}