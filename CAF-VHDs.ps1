# Collecting, Analyzing and Fixing VM VHDs

. "$PSScriptRoot\Common\ShoutOut.ps1"
. "$PSScriptRoot\Common\Run-Operation.ps1"
. "$PSScriptRoot\Common\Steal-RegKey.ps1"


<# Collect, Analyze and Fix VHDs
 Wishlist:
    - Use Mount-DiskImage instead DISM /Mount-Image to set up the disks. This would allow us to handle snapshot-vhds (avhd(x) files)
    - Inject Scheduled-Task instead of using registry RUN-key


.SYNOPSIS
    Looks for VHDs within the given directory, analyzes them, produces a hashtable with the acquired information and applies changes according to the supplied configuration.
 
.PARAMETER VHDDir
    The Directory to scan for VHDs.

.PARAMETER Configuration
    The configuration object to use when making changes to any Windows system volumes found. Supported settings:
        - Under the [International] key
            - SystemLocale: System locale to apply to the images (e.g. en-US).
            - UserLocale: Default user locale to apply to the images (e.g. en-US).
            - InputLocale: Default input locale(s) to apply to the images (e.g. 0409:0000041D).
            - UILanguage: Default UI Language to apply to the images (e.g. en-US).
            - TimeZone: Time zone for the computer (e.g. "W. Europe Standard Time").
.PARAMETER AutorunFiles
    Files that should be copied to the Windows images and set to autorun (.bat, .ps1 or .exe).
.PARAMETER VHDMountDir
    The directory to use as a mount point for the disks (must be empty). If this argument is omitted, a new directory will be created under C:\
.PARAMETER SymLinkDir
    Directory to use when creating temporary symbolic links.
 #>
function CAF-VHDs {
    param(
        $VHDDir="C:\Program Files",
        $Configuration = @{
            International=@{
                SystemLocale="en-US"
                UserLocale  ="en-US"
                InputLocales="0409:0000041D"
                UILanguage  ="en-US"

                GeoID       = 221
                Timezone    ="W. Europe Standard Time"
            }
        },
        $AutorunFiles = (ls "$PSScriptRoot\CAFAutorunFiles\*" | % { $_.FullName }),
        $VHDMountDir = $null,
        $SymlinkDir = "C:\"
    )



    $usingTmpMountDir = $false

    if (!$VHDMountDir) {
        $VHDMountDir = "C:\{0:X}" -f (Get-Date).Ticks
        { mkdir $VHDMountDir } | Run-Operation | Out-Null
        $usingTmpMountDir = $true
    }

    $CAFStartTime = Get-Date

    if ($VHDDir -notmatch "[\\/]$") { $VHDDir += "\" }
    if ($SymlinkDir -notmatch "[\\/]$") { $SymlinkDir += "\" }
    
    shoutOut "Running as '$($Env:USERNAME)'..."

    shoutOut "Initializing VHD records..." Cyan
    $VHDFiles = ls -Recurse $VHDDir -File | ? { $_.Name -match "\.(a)?vhd(x)?$" }
    $VHDRecords = $VHDFiles | % {
        $r = @{
            File=$_.FullName
            FileItem=$_
            VHD=(Get-VHD -Path $_.FullName)
            IsParent=$false
            IsBaseDisk=$false
        }
        $r.IsChild = if ($r.VHD.ParentPath) { $true } else { $false }
        $r
    }
    shoutOut "Done!" Green

    
    shoutOut "Discovering parent relationships..." Cyan
    foreach ($record in $VHDRecords) {
        if ($record.VHD.ParentPath) {
            $parentRecord = $VHDRecords | ? { $_.File -eq $record.VHD.ParentPath }
            if ($parentRecord) {
                shoutOut "'$($parentrecord.File)' is parent of '$($record.File)'" White
                $parentRecord.IsParent = $true
            }
        } else {
            $record.ISBaseDisk = $true
        }
    }
    shoutOut "Done!" Green

    
    shoutOut "Identifying VHDs with Windows system volumes..." Cyan
    $VHDRecords | % {
        shoutOut "Checking " Cyan -NoNewline
        shoutOut "$($_.File)" Gray
        if ($_.IsParent) { 
            shoutOut " Skipping! (is a parent)" White
            return
        }

        $VHDfile = $_.File
        $UsingSymlink = $false

        # Dism can get information for .avhd(x) files, but will not accept
        # files with such an extension as an argument. So we create a
        # symbolic link with an accepted extension.
        #
        # [UPDATE 20170301] It seems that we cannot mount avhd-files at all,
        # the format is apparently different somehow.
        if ($VHDFile -match ".a(?<ext>vhd(x)?)$") { 
            $UsingSymlink = $true
            $VHDFile = "$SymlinkDir`_serviceSymlink.$($Matches.ext)"
            { cmd /C "mklink `"$VHDFile`" `"$($_.File)`"" } | Run-Operation | Out-Null
        }

        $r = { dism /Get-ImageInfo /ImageFile:"$VHDfile" } | Run-Operation
        $rf = $r -join "`n"
        if ($rf -match "Error: (?<ErrorCode>(0x)?[0-9A-F]+)") {
            shoutOut " No" Red
            $_.ErrorCode = $Matches.ErrorCode
        } else {
            shoutOut " Yes" Green
            $_.Volumes = @()
            $i64c = New-Object System.ComponentModel.Int64Converter
            for($i = 0; $i -lt $r.Length; $i++) {
                # write-host $r[$i] -ForegroundColor Gray
                if ($r[$i] -match "^Index : (?<Index>[0-9]+)") {
                    $volume = @{ Index=$i64c.ConvertFrom($Matches.Index) }

                    if ($r[$i + 1] -match "Name : (?<Name>[^\n]+)") {
                        $volume.Name = $Matches.Name
                    }

                    if ($r[$i + 2] -match "Description : (?<Desc>[^\n]+)") {
                        $volume.Description = $Matches.Desc
                    }

                    if ($r[$i + 3] -match "Size : (?<Size>[^\sa-z]+) Bytes") {
                        $volume.Size = $i64c.ConvertFrom(($Matches.Size -replace "[^0-9]",""))
                    }

                    $_.Volumes += $volume
                }
            }
        }

        if ($UsingSymlink) {
            rm $VHDfile
        }
    }
    shoutOut "Done!" Green

    
    shoutOut "Analyzing and fixing the offline images..." Cyan
    $VHDRecords | % {
        
        shoutOut "$($_.File)" Gray -NoNewline
        if ($_.ErrorCode -or $_.IsParent) {
            shoutOut " Skip!" White
            return
        }

        shoutOut " Mounting as a Windows image..." Cyan
        

        $VHDfile = $_.File
        $UsingSymlink = $false

        # Dism can get mount .avhd(x) files, but will not accept
        # files with such an extension as an argument. So we create a
        # symbolic link with an accepted extension. 
        if ($VHDFile -match ".a(?<ext>vhd(x)?)$") { 
            $UsingSymlink = $true
            $VHDFile = "$SymlinkDir`_serviceSymlink.$($Matches.ext)"
            { cmd /C "mklink `"$VHDFile`" `"$($_.File)`"" } | Run-Operation | Out-Null
        }
        $r = {dism /Mount-Image /ImageFile:"$($VHDfile)" /MountDir:"$($VHDMountDir)" /Index:$($_.Volumes[0].Index) } | Run-Operation
        $rf = $r -join "`n"
        if ($rf -match "Error: (?<ErrorCode>(0x)?[0-9a-f]+)") {
            $_.MountErrorCode = $Matches.ErrorCode
            shoutOut " Failed ($($Matches.ErrorCode))" Red
            if ($UsingSymlink) {
                rm $VHDfile
            }

            return
        }

        $r = {dism /Image:"$($VHDMountDir)" /Get-CurrentEdition} | Run-Operation
        $rf = $r -join "`n"
        if ($rf -match "Current Edition : (?<Edition>[^\n]+)\n") {
            $_.WindowsEdition = $Matches.Edition
        } else {
            $_.WindowsEdition = "Unknown"
        }

        if ((Test-Path "$VHDMountDir\CAFAutorun")) { Remove-Item -Recurse -Force "$VHDMountDir\CAFAutorun" } #DEBUG

        if ( !(Test-Path "$VHDMountDir\CAFAutorun") ) {
            shoutOut "Creating the CAF autorun folder..." Cyan
            $item = New-Item "$VHDMountDir\CAFAutorun" -ItemType Directory
            shoutOut "Hiding the folder..." Cyan
            $item | Set-ItemProperty -Name Attributes -Value ([System.IO.FileAttributes]::Hidden)
            shoutOut "Populating the folder..."
            $AutorunFiles | % {
                if (!(Test-Path $_)) {
                    shoutOut "Missing source file: '$_'" Red
                    return
                }
                { xcopy "$_" "$VHDMountDir\CAFAutorun\" } | Run-Operation | Out-Null *> $null
            }
            
            shoutOut "Done!" Green

            
        }
        
        $rootKey = "HKLM\OFFLINE-SOFTWARE"
        shoutOut "Loading offline SOFTWARE hive..." Cyan
        {reg load $rootKey "$VHDMountDir\Windows\System32\config\SOFTWARE"} | Run-Operation | Out-Null
        $r = {reg query "$rootKey\"} | Run-Operation
        if (($r | ? { $_ -match "CAFSetup$" })) { "reg delete $rootKey\CAFSetup /f" | Run-Operation | Out-Null; $r = "reg query `"$rootKey\`"" | Run-Operation | Out-Null } #DEBUG
        
        
        if ( !($r | ? { $_ -match "CAFSetup$" }) ) {
            
            shoutOut "Setting up local CAF..." Cyan
            $CAFAutorunBootstrap =  { start Powershell -Verb RunAs -ArgumentList '-WindowStyle Hidden -ExecutionPolicy Bypass -NoProfile -Command echo Bootstrap; echo $Env:USERNAME; iex (gpv HKLM:\SOFTWARE\CAFSetup AutorunScript)' }
            $CAFAutorunScript = { echo ('Running CAFAutorun as {0}'-f ${Env:USERNAME}) ; ls C:\CAFAutorun | ? { $_.Name -match '.bat|.ps1' } | % { try{ & $_.FullName *>&1 } catch { Write-host $_ }  } }
            
            $operations = @(
                { reg add "$rootKey\CAFSetup"},
                { reg add $rootKey\CAFSetup /v AutorunDir /t REG_EXPAND_SZ /d C:\CAFAutorun },
                { reg add $rootKey\CAFSetup /v AutorunCount /t REG_DWORD /d 0 },
                { reg add $rootKey\CAFSetup /v AutorunBootstrap /t REG_SZ /d "$($CAFAutorunBootstrap.ToString())"},
                { reg add $rootKey\CAFSetup /v AutorunScript /t REG_SZ /d "$($CAFAutorunScript.ToString())"},
                { reg query $rootKey\CAFSetup }
            )

            $operations | % { Run-Operation $_ }  | Out-Null

            shoutOut "Done!" Green
        }

        if ( { reg query "$rootKey\Microsoft\Windows\CurrentVersion\Run" | ? { $_ -match "^\s*CAFAutorunTrigger" } } | Run-Operation |Out-Null) { shoutOut "Deleting old Trigger..." Cyan; { reg delete "$rootKey\Microsoft\Windows\CurrentVersion\Run" /v CAFAutorunTrigger /f } | Run-Operation | Out-Null } #DEBUG

        # The trigger script switches to a Powershell context and executes the Bootstrapper snippet, the bootstrapper
        # snippet then starts a new Powershell context that runs with elevated privilidges and calls the AutorunScript snippet.
        $r = { reg query "$rootKey\Microsoft\Windows\CurrentVersion\Run" } | Run-Operation
        if ( !($r | ? { $_ -match "^\s*CAFAutorunTrigger" }) ) {
            shoutOut "Adding CAF autorun trigger..." Cyan
            $r = { reg add "$rootKey\Microsoft\Windows\CurrentVersion\Run" /v CAFAutorunTrigger /t REG_SZ /d "Powershell -Command iex (gpv HKLM:\SOFTWARE\CAFSetup AutorunBootstrap)" } | Run-Operation
            $r | % { shoutOut "`t| $_" White }
        }


        shoutOut "Making Quality of Life changes to hive..." Cyan

        if (Test-Path 'HKLM:\OFFLINE-SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList\DefaultMediaCost') {
            { Steal-RegKey 'HKLM:\OFFLINE-SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList\DefaultMediaCost' } | Run-Operation | Out-Null
        }

        $operations = @(
            # Prevent UAC consent prompts for admins, as described @ http://www.ghacks.net/2013/06/20/how-to-configure-windows-uac-prompt-behavior-for-admins-and-users/
            "reg add $rootKey\Microsoft\Windows\CurrentVersion\Policies\System /v ConsentPromptBehaviorAdmin /t REG_DWORD /d 0 /f"
            # Set ethernet connections to be metered, to avoid frivolous downloads.
            "reg add '$rootKey\Microsoft\Windows NT\CurrentVersion\NetworkList\DefaultMediaCost' /v Ethernet /t REG_DWORD /d 2 /f"
        )


        $operations | % { Run-Operation $_ } | Out-Null
        shoutOut "Done!" Green

        
        shoutOut "Unloading registry...." Cyan
        { reg unload $rootKey } | Run-Operation | Out-Null


        $localeNameRegex = "[a-z]{2}-[a-z]{2}"
        $localeIdRegex1 = "[0-9a-f]{4}:[0-9a-f]{8}"
        $localeIdRegex2 = "[0-9a-f]{4}:\{[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\}"
        $localeRegex  = "($localeNameRegex|$localeIdRegex1|$localeIdRegex2)"
        
        shoutOut "Reseting culture to 'en-US'..." Cyan
        $r = { dism /Image:"$($VHDMountDir)" /Set-AllIntl:"en-US" } | Run-Operation
        $rf = $r -join "`n"
        
        if ($Configuration.International -is [hashtable]) {
            shoutOut "Verifying culture settings against the configuration..." Cyan

            $intl = $configuration.International

            shoutOut "Loading culture settings..." Cyan
            $r = { dism /Image:"$($VHDMountDir)" /Get-Intl } | Run-Operation | Out-Null
            $rf = $r -join "`n"
            

            $settings = @{
                # Name             #Set-switch        # Identifying pattern
                "UILanguage"   = @("Set-UILang",      "Default System UI language : (?<current>$localeRegex)")
                "SystemLocale" = @("Set-SysLocale",   "System locale : (?<current>$localeRegex)")
                "UserLocale"   = @("Set-UserLocale",  "User locale for default user : (?<current>$localeRegex)")
                "InputLocales" = @("Set-InputLocale", "Active keyboard\(s\) : (?<current>$localeRegex(, $localeRegex)*)")
                "Timezone"     = @("Set-TimeZone",    "Default time zone : (?<current>[^\n]+)")
            }

            foreach ($setting in $settings.GetEnumerator()) {
                $key = $setting.Key
                $v = $setting.Value
                if (($rf -match $v[1])) {
                    $_[$key] = $Matches.current
                    if ( $Intl[$key] -and ($Intl[$key] -ne $_[$Key]) ) {
                        { dism /Image:"$($VHDMountDir)" /$($v[0]):$($Intl[$key]) } | Run-Operation | Out-Null
                    }
                }
            }

            <#
            $key = "UILanguage"
            if ($intl[$key] -and ($rf -match "Default System UI language : (?<uiLanguage>$localeRegex)")) {
                $key = "UILanguage"
                $_[$key] = $Matches.uiLanguage
                if ( $Configuration[$key] -and ($Configuration[$key] -ne $_[$Key]) ) {
                    { dism /Image:"$($VHDMountDir)" /Set-UILang:$($Configuration[$key]) } | Run-Operation
                }
            }

            $key = "SystemLocale"
            if ($rf -match "System locale : (?<systemLocale>$localeRegex)") {
                $_[$key] = $Matches.systemLocale
                if ( $Configuration[$key] -and ($Configuration[$key] -ne $_[$Key]) ) {
                    { dism /Image:"$($VHDMountDir)" /Set-SysLocale:$($Configuration[$key]) } | Run-Operation
                }
            }
            if ($rf -match "User locale for default user : (?<userLocale>$localeRegex)") {
                $key = "UserLocale"
                $_[$key] = $Matches.userLocale
                if ( $Configuration[$key] -and ($Configuration[$key] -ne $_[$Key]) ) {
                    { dism /Image:"$($VHDMountDir)" /Set-UserLocale:$($Configuration[$key]) } | Run-Operation
                }
            }
            if ($rf -match "Active keyboard\(s\) : (?<keyboards>$localeRegex(, $localeRegex)*)") {
                $key = "InputLocales"
                $_[$key] = $Matches.keyboards
                if ( $Configuration[$key] -and ($Configuration[$key] -ne $_[$Key]) ) {
                    { dism /Image:"$($VHDMountDir)" /Set-InputLocale:$($Configuration[$key]) } | Run-Operation
                }
            }
            if ($rf -match "Default time zone : (?<timezone>[^\n]+)") {
                $_.Timezone = $Matches.timezone
                $key = "Timezone"
                $_[$key] = $Matches.timezone
                if ( $Configuration[$key] -and ($Configuration[$key] -ne $_[$Key]) ) {
                    { dism /Image:"$($VHDMountDir)" /Set-TimeZone:'$($Configuration[$key])'} | Run-Operation
                }
            }
            #>
        }

        $r = { dism /Unmount-Image /MountDir:"$($VHDMountDir)" /Commit } | Run-Operation
        $rf = $r -join "`n"
        if ($rf -match "Error: (?<ErrorCode>(0x)?[0-9a-f]+)") {
            $_.UnmountErrorCode = $Matches.ErrorCode
        }

        if ($UsingSymlink) {
            rm $VHDfile
        }
        ShoutOut "Done!" Green
    }

    if ($usingTmpMountDir) {
        rm -Recurse $VHDMountDir
    }

    $CAFDuration = (Get-Date) - $CAFStartTime

    shoutOut "CAF Done! ($($CAFDuration.TotalSeconds) seconds)" Green

    return $VHDRecords
}