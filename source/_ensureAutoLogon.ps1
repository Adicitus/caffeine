#_ensureAutoLogon.ps1
function _ensureAutoLogon {
    param(
        $Setup,
        $TmpDir,
        $LogFile
    )

    if ($autologon = $setup.'Credential-AutoLogin') {

        if (!$autologon.domain -or ($autologon.domain -eq '.')) {
            $user = Get-LocalUser -Name $autologon.username -ErrorAction SilentlyContinue

            if (!$user) {
                $params = @{
                    name = $autologon.username
                }

                if ($autologon.password) {
                    $params.password = ConvertTo-SecureString -String $autologon.password -AsPlainText -Force
                    $params.passwordNeverExpires = $true
                } else {
                    $params.noPassword = $true
                }

                $user = New-LocalUser @params -AccountNeverExpires
                $adminsGroup = Get-LocalGroup -SID S-1-5-32-544

                Add-LocalGroupMember -Group $adminsGroup -Member $user
            }
        }

        $templateFile = "$PSScriptRoot\.assets\templates\winlogon.tmplt.reg"
        $outputFile = "$tmpDir\winlogon.reg"

        "Generating .reg file from template ('{0}') -> {1}" -f $templateFile, $outputFile >> $LogFile
        Render-template $templateFile $autologon > $outputFile
        "Importing the .reg file..." >> $LogFile
        reg import $outputFile >> $LogFile
    }
}