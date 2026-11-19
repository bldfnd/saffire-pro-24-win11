<#
.SYNOPSIS
    Removes the Windows Driver Policy {8F9CB695-...} that blocks legacy
    cross-signed kernel drivers on Windows 11 24H2/25H2 (April 2026+).

.DESCRIPTION
    Tries the Microsoft-documented command first:
        CiTool.exe --remove-policy "{8F9CB695-5D48-48D6-A329-7202B44607E3}"
    On builds where CiTool refuses (0x80070005, even as SYSTEM), the policy file is
    backed up and removed from the EFI System Partition instead.

    A reboot is required for the change to take effect.

.PARAMETER Force
    Remove the policy file from the ESP even if CiTool does not report the policy.

.NOTES
    Security: this re-enables trust for the deprecated cross-signed driver program.
    Use only if you need a legacy driver. The original policy file is backed up
    to .\backup\ and can be restored (see README).
#>

param([switch]$Force)

# --- self-elevate ---
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    if ($Force) { $args += '-Force' }
    Start-Process powershell -Verb RunAs -ArgumentList $args
    exit
}

$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot
$log  = Join-Path $root 'fix-policy.log'
$bak  = Join-Path $root 'backup'
$guid = '8F9CB695-5D48-48D6-A329-7202B44607E3'

function Log($t) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $t
    $line | Out-File -FilePath $log -Append -Encoding utf8
    Write-Host $line
}

function Test-PolicyLoaded {
    $out = & cmd.exe /c '"%WINDIR%\System32\CiTool.exe" -lp -json < nul 2>&1'
    return (($out | Out-String).IndexOf('8f9cb695') -ge 0)
}

"=== FIX POLICY $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Out-File -FilePath $log -Append -Encoding utf8
New-Item -ItemType Directory -Path $bak -Force | Out-Null

$present = Test-PolicyLoaded
Log ("policy {0} loaded: {1}" -f $guid, $present)

if (-not $present -and -not $Force) {
    Log 'nothing to do: the policy is not loaded'
    exit 0
}

# 1. documented way
Log 'trying CiTool --remove-policy'
$cmdline = ('"%WINDIR%\System32\CiTool.exe" --remove-policy "{%GUID%}" < nul 2>&1') -replace '%GUID%', $guid
$out = & cmd.exe /c $cmdline
$text = ($out | Out-String)
if ($text -match '0x[0-9A-Fa-f]{8}') {
    Log ('  CiTool returned: ' + ($text -replace "`r`n", ' '))
} else {
    Log '  CiTool: command executed'
}

# 2. fallback: remove the .cip from the EFI System Partition
if (Test-PolicyLoaded -or $Force) {
    Log 'CiTool did not help, removing the policy file from the EFI System Partition'
    & cmd.exe /c 'mountvol S: /s < nul 2>&1' | Out-Null
    if (-not (Test-Path 'S:\')) {
        Log 'ERROR: could not mount the EFI System Partition'
    } else {
        $dir = 'S:\EFI\Microsoft\Boot\CiPolicies\Active'
        $files = Get-ChildItem $dir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '8f9cb695' }
        if (-not $files) { Log '  no policy file on the ESP' }
        foreach ($f in $files) {
            try {
                Copy-Item $f.FullName (Join-Path $bak ('esp_' + $f.Name)) -Force
                Remove-Item $f.FullName -Force -ErrorAction Stop
                Log ('  removed: ' + $f.Name)
            } catch {
                Log ('  failed to remove ' + $f.Name + ': ' + $_.Exception.Message)
            }
        }
        & cmd.exe /c 'mountvol S: /d < nul 2>&1' | Out-Null
    }
}

Start-Sleep -Seconds 1
if (Test-PolicyLoaded) {
    Log 'RESULT: policy is still loaded in this session - reboot and run this script again'
} else {
    Log 'RESULT: policy removed. Reboot to take effect.'
}
