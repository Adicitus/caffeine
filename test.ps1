#test.ps1

param($Arg)

Get-PSCallStack | select -first 1

# & "$PSScriptRoot\_ensureElevation.ps1"
# Pause