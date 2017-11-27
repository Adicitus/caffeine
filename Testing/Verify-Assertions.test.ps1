$caffeineRoot="$PSScriptRoot\.."

. "$caffeineRoot\Common\ShoutOut.ps1"
. "$caffeineRoot\Common\Parse-ConfigFile.ps1"
. "$caffeineRoot\Verify-Assertions.ps1"


$logFile = "$PSSCriptRoot\Verify-Assertions.test.ini.log"
$resultsDir = "$PSSCriptRoot\Results"
$_ShoutOutSettings.LogFile = $logFile

if ( !(Get-Item $resultsDir | ? { $_.Mode -match "^d" }) ) {
    mkdir $resultsDir
}

$tests = ls "$PSScriptRoot\*test.ini" | Sort-Object -Property Name

$tests | % {
    $conf = Parse-ConfigFile $_.FullName
    Write-Host "$("="*10) $($conf.Test.Name) ".PadRight(80,"=") -ForegroundColor Magenta
    Verify-Assertions $conf -logFile ("{0}\{1}.json" -f $resultsDir,$conf.Test.Name)
}

Write-Host "$("="*10) Checking the Results ".PadRight(80,"=") -ForegroundColor Cyan
Get-ChildItem $resultsDir -Filter "*.json" | % {
    Write-Host "Checking '$_'..." -NoNewline -ForegroundColor Cyan
    $rs = $_ | Get-Content | ConvertFrom-Json
    $errorFound = $false
    $rs | % {
        $r = $_
        $msg = $null
        switch -Regex ($r.Name) {
            "^Fail" {
                if ($r.Passed) {
                    $msg = ("'{0}' Expected to FAIL, but PASSED instead!" -f $r.Name)
                    $errorFound = $true
                }
            }
            default {
                if (!$r.Passed) {
                    $msg = ("'{0}' Expected to PASS, but FAILED instead!" -f $r.Name)
                    $errorFound = $true
                }
            }
        }
        if ($msg -ne $null) {
            $msg | Write-Host -ForegroundColor Red
        }
    }
    if (!$errorFound) {
        Write-Host "Clear!" -ForegroundColor Green
    }
}