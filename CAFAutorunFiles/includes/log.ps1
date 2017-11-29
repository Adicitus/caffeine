$logFile = "C:\CAF.log"
$log = {
    param($msg)
    Write-Host $msg
    if ($msg -isnot [String]) {
        $msg = $msg | Out-String
    }
    ("{0}: {1}" -f (Get-Date),$msg) >> $logFile
}