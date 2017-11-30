param($onRearmAction)

. "$PSScriptRoot\log.ps1"

# Prompt for consent to restart the machine.
# [MessageBox] is not an option since availability is spotty.

$prompt = {
    param ($action, $switch)
    $restartQuery = {
        Write-Host "Some of the licenses on this machine were about to expire and have been reactivated."
        Write-Host "The machine needs to be $action in order for these changes to finish."
        $r = ""
        while ($r -notmatch '^y|yes|yeah|yep|n|no|nope|nah$') {
            $r = Read-Host -Prompt 'Would you like to restart now? (Y/N)'
            . $log "Shutdown?: $r"
            if ($r -match '^y|yes|yeah|yep$' ) {
                shutdown $switch /t 5
            }
        }
    }

    . $restartQuery

}

switch -Regex ($onRearmAction) {
    "promptShutdown" {
        . $log "OnRearm action: prompt for shutdown"
        . $prompt "Shut down" "/s"
        break
    }
    "promptRestart" {
        . $log "OnRearm action: prompt for restart"
        . $prompt "restart" "/r"
        break
    }
    "Shutdown" {
        . $log "OnRearm action: shutdown"
        shutdown /s /t 0
        break
    }
    "Restart" {
        . $log "OnRearm action: Restart"
        shutdown /r /t 0
        break
    }
    default {
        . $log "Default OnRearm action: shutdown"
        Shutdown /s /t 0
        break
    }
}