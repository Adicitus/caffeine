
function Verify-Assertions{
    param(
        [hashtable]$conf,
        $logFile="C:\caffeinate.asserts.json"
    )

    $assertTypes = @{
        Assert=@{
            Check = { param($r) $r.GetType() -ne [System.Management.Automation.ErrorRecord] }
        }
        AssertException=@{
            Check = { param($r) $r.GetType() -eq [System.Management.Automation.ErrorRecord] }
        }
        AssertTrue=@{
            Check = { param($r) if ($r) { $true } else { $false } }
        }
        AssertFalse=@{
            Check = { param($r) if (!$r) { $true } else { $false } }
        }
    }

    $assertKeys = $conf.Keys | ? { $_ -match "^(?<type>Assert[^:\s]*):(?<name>.+)" } | % { @{ Key=$_; Name=$Matches.Name; Type=$Matches.Type } }
    shoutOut "Found the following Assert sections:"
    shoutOut ($assertKeys | % Key)

    $asserts = $assertKeys | ? { $conf[$_.Key].Test } | % {
        $assert = @{
            Name=$_.Name
            Type=$_.Type
            Test=$conf[$_.Key].Test
        }

        if ($t = $conf[$_.Key].Type) {
            if ( $assertTypes.ContainsKey($t) ) {
                $assert.type = $t
            } else {
                shoutOut ("Invalid Assert type specified for '{0}' ('{1}'). Available types are: {2}" -f $_.Name,$t,($assertTypes.Keys -join ", ")) Red
            }
        }

        if ($d = $conf[$_.Key].Description) {
            $assert.Description = $d
        } else {
            $assert.Description = "None provided."
        }

        $assert
    }

    shoutOut ("Found {0} valid asserts..." -f @($asserts).Count)

    $result = @()

    $asserts | % {
        shoutOut ("Checking '{0}' ({1})..." -f $_.Name, $_.Type) -NoNewLine
        $r = try {
            Invoke-Expression $_.Test -ErrorAction Stop
        } catch {
            $_
        }
        $p = if (. $assertTypes[$_.Type].Check $r) { $true } else { $false }
        $msg = if($p) { "Passed!" } else { "Failed!" }
        shoutOut $msg
        $result += @{ Name=$_.Name; Type=$_.Type; Description=$_.Description; Passed=$p }
    }
    
    shoutOut "Outputting results to '$logFile'..."
    $json = $result | ConvertTo-Json
    [System.IO.File]::WriteAllText("$logFile", $json)
}