
#requires -Modules ACGCore


function _peelPodFile($podFile){
    shoutOut "Evaluating '$($PodFile.FullName)'... " cyan -NoNewline
    switch -Regex ($PodFile.Name) {
        # File is an FS hive.
        "\.hive\.vhd(x)?$" {
            shoutOut "Hive Disk"
            # Mount disk, attach to correct directory using symlink,
            # add an task on startup to mount the disk.

            { Install-HiveDisk $PodFile } | Invoke-ShoutOut -OutNull
            break;
        }
        # Files is a MOCSetup-style clusterpod.
        "\.archives\.vhd(x)?$" { # proposed naming convention
            ShoutOut "Cluster Pod"
            { Unpack-ArchiveDisk $PodFile } | Invoke-ShoutOut -OutNull
            break;
        }
        "\.vhd(x)?$" { # Legacy entry for backwards compatibility with MOCSetup
            ShoutOut "Cluster Pod (Legacy)"
            { Unpack-ArchiveDisk $PodFile } | Invoke-ShoutOut -OutNull
            break;
        }
        # File is the first part in a classic multi-part RAR file.
        "\.part[0]*1\.rar$" {
            shoutOut "Multipart RAR"
            # Unpack to comment path, or to C:\
            { Unpack-RARFile $PodFile } | Invoke-ShoutOut -OutNull
            break;
        }
        # File is a non-first part of a classic multipart RAR file.
        "\.part[0-9]+\.rar$" {
            shoutOut "Skip!"
            break; # ignore
        }
        # File is a single-chunk classic RAR file.
        "\.rar$" {
            shoutOut "RAR"
            # Unpack to comment path, or to C:\
            { Unpack-RARFile $PodFile } | Invoke-ShoutOut -OutNull
            break;
        }
        # File is the first part in a multi-part SFX RAR file.
        "\.part[0]*1\.exe$" {
            shoutOut "Multipart SFX RAR"
            # Unpack to comment path, or to C:\
            { Unpack-RARFile $PodFile } | Invoke-ShoutOut -OutNull
            break;
        }
        # File is the non-first part in a multi-part SFX RAR file.
        "\.part[0-9]+\.exe$" {
            shoutOut "Skip!"
            break; # ignore
        }
        # File might be a SFX RAR file mean for unpacking, or it
        # might be program we shouldn't touch.
        "\.exe$" {
            # Test with WinRAR? Ignore?
            shoutOut "Unable to determine Pod type..." Warning
        }
        default {
            shoutOut "Not a pod! Skipping" Warning
        }
    }
}