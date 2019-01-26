<#
.SYNOPSIS
Verifies a set of assertions provided in the configuration object.

.DESCRIPTION
Verifies a set of assertions provided in the configuration object. Assertions are sections
who's name starts with "Assert", containing "Test" declarations:

[Assert[(Exception|True|False)][:]<Assertion name>]
Test=<Command to run>

While the section title must start with "Assert", writing "AssertException", "AssertTrue" or
"AssertFalse" will change the type of assertion type:

Assert: Fails if any of the tests result in an Exception or ErrorRecord.
AssertException: Passes if all of the tests result in an Exception or ErrorRecord.
AssertTrue: Passes if and only if all test results evaluate to $true.
AssertFalse: Passes if and only if all test results evaluate to $false.

DEPRECATED: The assert type can be overriden using a "Type" declaration (Type=<Type of assert>).

To provide a bit more information about an assertion a "Description" declaration
can be used (Description=<description of the assertion>).

#>
function Verify-Assertions{
    param(
        [hashtable]$conf,
        $logFile="C:\caffeinate.asserts.json"
    )

    $assertTypes = @{
        Assert=@{
            Check = { param($r) ($r -eq $null) -or ($r.GetType() -ne [System.Management.Automation.ErrorRecord]) }
        }
        AssertException=@{
            Check = { param($r) ($r -ne $null) -and ($r.GetType() -eq [System.Management.Automation.ErrorRecord]) }
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

        # An explicit type declaration overrides the implicit type declaration from the section header.
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
        shoutOut ("Checking '{0}' ({1}, {2} lines)..." -f $_.Name, $_.Type, @($_.Test).length) -NoNewLine

        $assert = $_
        $rs = New-Object System.Collections.ArrayList

        $OldErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = "Stop"

        $_.Test | % {
            $t = $_
            $r = try {
                Invoke-Expression $t
            } catch {
                $_
            }
            $wrap = New-Object System.Collections.ArrayList
            $wrap.add($t)
            $wrap.add($r)
            $rs.Add($wrap)
        }

        $ErrorActionPreference = $OldErrorActionPreference

        $failedTests = @()
        $p = $true
        if ($rs.length -eq 0) {
            $p = $false
        } else {
            $rs | % {
                if ( !(. $assertTypes[$assert.Type].Check $_[1]) ) {
                    $p = $false
                    $failedTests += $_[0]
                }
            }
        }
        $msg = if($p) { "Passed!" } else { "Failed!" }
        shoutOut $msg
        $result += @{ Name=$_.Name; Type=$_.Type; Description=$_.Description; Passed=$p; FailedTests=$failedTests }
    }
    
    shoutOut "Outputting results to '$logFile'..."
    $json = $result | ConvertTo-Json
    [System.IO.File]::WriteAllText("$logFile", $json)
}