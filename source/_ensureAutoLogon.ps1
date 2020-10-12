#_ensureAutoLogon.ps1
function _ensureAutoLogon {
    param(
        $Setup,
        $TmpDir,
        $LogFile
    )

    # $setup = Parse-ConfigFile $setupFile

    if ($autologon = $setup.'Credential-AutoLogin') {
        $templateFile = "$PSScriptRoot\.assets\templates\winlogon.tmplt.reg"
        $outputFile = "$tmpDir\winlogon.reg"

        "Generating .reg file from template ('{0}') -> {1}" -f $templateFile, $outputFile >> $LogFile
        Render-template $templateFile $autologon >> $outputFile
        "Importing the .reg file..." >> $LogFile
        reg import $outputFile >> $LogFile
    }
}