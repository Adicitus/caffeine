# Collecting, Analyzing and Fixing VM VHDs

#requires -Modules ACGCore

. "$PSScriptRoot\_configureOfflineHKLM.ps1"
. "$PSScriptRoot\_configureOfflineHKUs.ps1"


<# Collect, Analyze and Fix VHDs
 Wishlist:
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

.NOTES
    - Uses Mount-VHD instead of DISM /Mount-Image so that we can handle avhd(x) files.
    - Uses Common\Bin\dism.exe instead of native dism command to avoid having to install the latest version of the ADK in every deployment.

 #>
function _cafVHDs {
    param(
        $VMFolders="C:\Program Files",
        $Configuration = @{
            International=@{
                AllIntl="en-US"
                SystemLocale="en-US"
                UserLocale  ="en-US"
                InputLocales="0409:0000041D"
                UILanguage  ="en-US"

                GeoID       = 221
                Timezone    ="W. Europe Standard Time"
            }
        },
        $AutorunFiles = (ls "$PSScriptRoot\CAFAutorunFiles\*" | % { $_.FullName }),
        $ExcludePaths = @(),
        $VHDMountDir = $null,
        $SymlinkDir = "C:\"
    )

    $dism = "$PSScriptRoot\bin\DISM\dism.exe"
    if ( !(Test-Path $dism) ) {
        $dism = "dism"
    }

    "Using the following DISM.exe: '{0}'" -f $dism | shoutout

    $CAFStartTime = Get-Date

    $VMFolders = $VMFolders | % { if ($_ -notmatch "[\\/]$") { "$_\" } else { $_ } }
    if ($SymlinkDir -notmatch "[\\/]$") { $SymlinkDir += "\" }
    
    shoutOut "Running as '$($Env:USERNAME)'..."

    shoutOut "Initializing VHD records..." Cyan
    $t = $VMFolders | ls -Recurse -File | ? { $_.Name -match "\.(a)?vhd(x)?$" }
    $t = $t | ? { $p = $_.FullName; -not ($excludePaths | ? { $p -like $_ }) }
    shoutOut ("Found {0} VHD files..." -f @($t).Count)
    $VHDFiles = $t |Sort -Property FullName | Get-Unique
    shoutOut ("{0} non-duplicates..." -f @($VHDFiles).Count)

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
            $record.IsBaseDisk = $true
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
        if ($VHDFile -match ".a(?<ext>vhd(x)?)$") {
            shoutOut "Disk is an snapshot disk, setting up symbolic link trick..." Cyan
            $UsingSymlink = $true
            $VHDFile = "$SymlinkDir`_serviceSymlink.$($Matches.ext)"
            { cmd /C "mklink `"$VHDFile`" `"$($_.File)`"" } | Run-Operation | Out-Null
            shoutOut "Done!" Green
        }

        $r = { . $dism /Get-ImageInfo /ImageFile:"$VHDfile" } | Run-Operation
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
            shoutout "Removing symlink... " Cyan -NoNewline
            rm $VHDfile
            shoutOut "Done!" Green
        }
    }
    shoutOut "Done!" Green

    if (($c = $Configuration["CAF-VHDs"]) -and ($c.ContainsKey("NoFix"))) {
        $noFixPaths = @($c.NoFix)
    } else {
        $noFixPaths = @()
    }
    
    if (($c = $Configuration["CAF-VHDs"]) -and ($c.ContainsKey("Fix"))) {
        $fixPaths = @($c.Fix)
    } else {
        $fixPaths = @()
    }
    
    shoutOut "Analyzing and fixing the offline images..." Cyan
    $VHDRecords | % {
        
        $record  = $_

        shoutOut "$($record.File)" Gray -NoNewline
        if ($record.ErrorCode -or $record.IsParent) {
            shoutOut " Skip!" White
            return
        }

        shoutOut " Mounting as a VHD..." Cyan
        

        $VHDfile = $record.File
        $currentVHD = Get-VHD $VHDfile


        $r = { $currentVHD | Mount-VHD } | Run-Operation
        if ($r -is [System.Management.Automation.ErrorRecord]) {
            shoutOut " Failed to mount the VHD!" Red
            return
        }

        $currentVHD = $currentVHD | Get-VHD
        $disk = $currentVHD | Get-Disk

        $partitions = $disk | Get-Partition

        $partitions | % {

            #-----------------------------------------------------------------#
            #                         Start of Analysis                       #
            #   In this section we only gather information, nothing here      #
            #   should modify the volume in any way.                          #
            #-----------------------------------------------------------------#
            $partition = $_
            $volume = $partition | get-Volume
            $volumePath = Find-VolumePath $volume -FirstOnly

            if (!$volumePath) {
                shoutOut "No path available to partition #$($partition.PartitionNumber), skipping..."
                return
            } else {
                shoutOut "Partition #$($partition.PartitionNumber) has a path '$($volumePath)'." Green
            }
            
            $VHDMountDir = $volumePath

            $r = {. $dism /Image:"$($VHDMountDir)" /Get-CurrentEdition} | Run-Operation
            $rf = $r -join "`n"

            if ($rf -match "Error\s*: (?<error>(0x)?[0-9a-f]+)") {
                shoutOut "Unable to find a Windows installation at '$VHDMountDir'" Red
                return
            }

            if ($rf -match "Current Edition : (?<Edition>[^\n]+)\n") {
                $record.WindowsEdition = $Matches.Edition
            } else {
                $record.WindowsEdition = "Unknown"
            }
            
            #-----------------------------------------------------------------#
            #                          End of Analysis                        #
            #-----------------------------------------------------------------#

            if (($noFixPaths | ? { $record.File -like "$_*" }) -and !($fixPaths | ? { $record.File -like "$_*" })) {
                shoutOut ("'{0}' is in a path marked NoFix, skipping..." -f $record.File)
                return
            }
            #-----------------------------------------------------------------#
            #                          Start of Fixing                        #
            #   In this section we mnake any necessary changes to the volume. #
            #-----------------------------------------------------------------#

            if ((Test-Path "$VHDMountDir\CAFAutorun")) { Remove-Item -Recurse -Force "$VHDMountDir\CAFAutorun" } #DEBUG

            if ( !(Test-Path "$VHDMountDir\CAFAutorun") ) {
                shoutOut "Creating the CAF autorun folder..." Cyan
                $item = New-Item "$VHDMountDir\CAFAutorun" -ItemType Directory
                shoutOut "Hiding the folder..." Cyan
                $item | Set-ItemProperty -Name Attributes -Value ([System.IO.FileAttributes]::Hidden)

            }

            if ($fs = ls "$VHDMountDir\CAFAutorun\*" ) {
                shoutOut "Clearing out the CAFAutorun folder..." Cyan
                $fs | rm -Recurse -Force
                shoutOut "Done!" Green
            }
            shoutOut "Populating the CAFAutorun folder..."
            $AutorunFiles | % {
                if (!(Test-Path $_)) {
                    shoutOut "Missing source file: '$_'" Red
                    return
                }
                { Copy-Item "$_" "$VHDMountDir\CAFAutorun\" -Recurse } | Run-Operation | Out-Null
            }
            
            shoutOut "Done!" Green

            if ($vhdConfig = $Configuration[$record.FileItem.Name]) {

                if ($caffeineDir = $vhdConfig.InstallCaffeineTo) {
                    shoutOut "Installing Caffeine at '$caffeineDir'..."
                    $destPath = "$VHDMountDir\$caffeineDir"
                    mkdir $destPath
                    cp "$PSScriptRoot\..\*" $destPath -Recurse
                    $installScript = "$VHDMountDir\CAFAutorun\Install-Caffeine.ps1"
                    ('rm "$PSCommandPath";. "C:\{0}\Caffeinate.ps1"' -f $caffeineDir) | Out-File $installScript -Encoding utf8 -Force

                    shoutOut "Installing dependencies..."
                    $dstrootpath = "{0}\PSmodules" -f $VHDMountDir

                    "ShoutOut", "ACGCore" | % {
                        $n = $_
                        "Installing '{0}'..." -f $n | shoutOut

                        try {

                            $src = Get-Module $_ -ListAvailable
                            $srcpath = $m.Path | Split-Path -Parent

                            { robocopy $srcpath "$dstrootpath\$n" /S } | Run-Operation

                            "Done!" | shoutOut -MsgType Success
                        } catch {
                            "Failed to install '{0}'!" -f $n | shoutOut -MsgType Error
                            $_ | shoutOut
                        }

                    }

                }
                if ($jobFile = $vhdConfig.JobFile) {
                    shoutOut "Trying to include a job file... ('$jobFile')"
                    if ( Test-Path $jobFile ) {
                        shoutOut "Including '$jobFile'..."
                        $jobFileDestDir = "$VHDMountDir\setup"
                        $jobFileDest = "$jobFileDestDir\setup.ini"

                        if (!(Test-Path $jobFileDestDir -PathType Container)) {
                            mkdir $jobFileDestDir
                        }

                        cp $jobFile $jobFileDest
                    } else {
                        shoutOut "Unable to find the desired job file!" Red
                    }
                }
                if (($alu = $vhdConfig.AutoLoginUser) -and ($alp = $vhdConfig.AutoLoginPassword)) {
                    if ( !($ald = $vhdConfig.AutoLoginDomain ) ) {
                        $ald = $null
                    }

                    $rmp = "HKLM\OFFLINE-SOFTWARE"
                    Run-Operation { reg load $rmp "$VHDMountDir\Windows\System32\Config\SOFTWARE" }

                    $winlogon = "$rmp\Microsoft\Windows NT\CurrentVersion\winlogon"
                    Run-Operation { reg add $winlogon /v AutoAdminLogon /t REG_SZ /d 1 /f }
                    Run-Operation { reg add $winlogon /v AutoLogonCount /t REG_DWORD /d 9999 /f }
                    Run-Operation { reg add $winlogon /v DefaultPassword /t REG_SZ /d 1 /f }
                    Run-Operation { reg add $winlogon /v DefaultUserName /t REG_SZ /d $alu /f }
                    if ( $ald -ne $null) {
                        Run-Operation { reg add $winlogon /v DefaultDomainName /t REG_SZ /d $ald /f }
                    }
                    Run-Operation { reg add $winlogon /v DefaultPassword /t REG_SZ /d $alp /f }

                    Run-Operation { reg unload $rmp }
                }
            }

            $localeNameRegex = "[a-z]{2}-[a-z]{2}"
            $localeIdRegex1 = "[0-9a-f]{4}:[0-9a-f]{8}"
            $localeIdRegex2 = "[0-9a-f]{4}:\{[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\}"
            $localeRegex  = "($localeNameRegex|$localeIdRegex1|$localeIdRegex2)"
        
            if ($Configuration.International -is [hashtable]) {
                shoutOut "Verifying culture settings against the configuration..." Cyan

                $intl = $configuration.International

                shoutOut "Loading culture settings..." Cyan
                $r = { . $dism /Image:"$($VHDMountDir)" /Get-Intl } | Run-Operation
                $rf = $r -join "`n"
            
                # Available International settings
                $settings = @{
                    # Name             #Set-switch        # Identifying pattern
                    "AllIntl"      = @("Set-AllIntl",     "")
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
                        $record["[found]$key"] = $Matches.current
                        if ( $Intl[$key] -and ($Intl[$key] -ne $Matches.current) ) {
                            $record["[applied]$key"] = $Intl[$key]
                            { . $dism /Image:"$($VHDMountDir)" /$($v[0]):$($Intl[$key]) } | Run-Operation | Out-Null
                            $r = { . $dism /Image:"$($VHDMountDir)" /Get-Intl } | Run-Operation
                            $rf = $r -join "`n"
                        }
                    }
                }
            }
        
            _configureOfflineHKLM $VHDMountDir $Configuration
            _ConfigureOfflineHKUs $VHDMountDir $Configuration

            #-----------------------------------------------------------------#
            #                           End of Fixing                         #
            #-----------------------------------------------------------------#
        }

        $r = { $currentVHD | Dismount-VHD } | Run-Operation
        if (($r | ? { $_ -is [System.Management.Automation.ErrorRecord] })) {
            shoutOut "Failed to dismount the VHD!" Red
            $_.UnmountError = $r
            shoutOut $r
        }

        ShoutOut "Done!" Green
    }

    $CAFDuration = (Get-Date) - $CAFStartTime

    shoutOut "CAF Done! ($($CAFDuration.TotalSeconds) seconds)" Green

    return $VHDRecords
}