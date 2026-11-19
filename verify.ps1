<#
.SYNOPSIS
    Prints the state of the Saffire driver, device nodes, driver policy and recent
    Code Integrity events. Works without administrator rights for the read-only parts.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\verify.ps1
#>

$ErrorActionPreference = 'Continue'

# make sure Cyrillic/Unicode output is not mangled in the console
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

function Line($t) { Write-Host $t }

Line ("=== Saffire state {0} ===" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))

$ok = $true

Line ''
Line '--- kernel services ---'
foreach ($s in 'Saffire', 'SaffireAudio', 'SaffireMidi') {
    $drv = Get-CimInstance Win32_SystemDriver -Filter "Name='$s'" -ErrorAction SilentlyContinue
    if ($drv) {
        Line ("  {0,-14} {1}" -f $s, $drv.State)
        if ($drv.State -ne 'Running') { $ok = $false }
    } else {
        Line ("  {0,-14} not registered" -f $s)
        $ok = $false
    }
}

Line ''
Line '--- device nodes ---'
$nodes = Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match 'Saffire' }
if (-not $nodes) {
    Line '  no Saffire devices found'
    $ok = $false
} else {
    foreach ($n in $nodes) {
        Line ("  {0,-44} {1}" -f $n.FriendlyName, $n.Status)
        if ($n.Status -ne 'OK') { $ok = $false }
    }
}

Line ''
Line '--- driver signature (installed files) ---'
foreach ($f in 'Saffire.sys', 'SaffireAudio.sys', 'SaffireMidi.sys') {
    $p = Join-Path $env:WINDIR "System32\drivers\$f"
    if (Test-Path -LiteralPath $p) {
        $sig = Get-AuthenticodeSignature -LiteralPath $p
        Line ("  {0,-18} {1}" -f $f, $sig.SignerCertificate.Subject)
    } else {
        Line ("  {0,-18} missing" -f $f)
    }
}

Line ''
Line '--- test signing / policy ---'
$bcd = (& bcdedit /enum '{current}' 2>&1 | Out-String)
foreach ($l in ($bcd -split "`r`n")) {
    if ($l -match 'testsigning') { Line ('  ' + $l.Trim()) }
}
try {
    $json = & cmd.exe /c '"%WINDIR%\System32\CiTool.exe" -lp -json < nul 2>&1'
    $present = (($json | Out-String).IndexOf('8f9cb695') -ge 0)
    Line ("  driver policy 8F9CB695 loaded: {0}" -f $present)
    if ($present) { $ok = $false }
} catch { Line '  CiTool not available (needs Windows 11 22H2+)' }

Line ''
Line '--- recent Code Integrity events for Saffire ---'
try {
    Get-WinEvent -LogName 'Microsoft-Windows-CodeIntegrity/Operational' -MaxEvents 60 -ErrorAction Stop |
        Where-Object { $_.Message -match 'Saffire' } |
        Select-Object -First 6 |
        ForEach-Object {
            Line ("  [{0:HH:mm:ss}] Id={1}: {2}" -f $_.TimeCreated, $_.Id,
                (($_.Message -replace "`r`n", ' ').Substring(0, [Math]::Min(140, $_.Message.Length))))
        }
    Line '  (3076 = audited, harmless; 3077 = blocked, policy is active again)'
} catch { Line ('  log: ' + $_.Exception.Message) }

Line ''
if ($ok) { Line 'RESULT: OK - driver loaded, no blocking policy.'; exit 0 }
else { Line 'RESULT: PROBLEM - see the lines above.'; exit 1 }
