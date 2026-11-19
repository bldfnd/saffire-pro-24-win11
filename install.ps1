<#
.SYNOPSIS
    Installs the original Focusrite Saffire driver (4.3.0.41017) on Windows 11
    24H2/25H2 after the blocking driver policy has been removed.

.DESCRIPTION
    1. reports Secure Boot state;
    2. removes the Windows Driver Policy via fix-policy.ps1 if it is still active;
    3. stages/installs the vendor driver from .\drivers\Saffire.inf if missing;
    4. restarts the FireWire device node.

    The driver files are NOT included in this repository. Put the unmodified vendor
    files into .\drivers\ (Saffire.inf, Saffire.sys, SaffireAudio.sys, SaffireMidi.sys,
    Saffire.cat).

.PARAMETER RepairOnly
    Do not touch the policy; only check/install the driver.

.PARAMETER SkipDeviceRestart
    Do not disable/enable the FireWire device node.
#>

param(
    [switch]$RepairOnly,
    [switch]$SkipDeviceRestart
)

# --- self-elevate ---
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    if ($RepairOnly) { $args += '-RepairOnly' }
    if ($SkipDeviceRestart) { $args += '-SkipDeviceRestart' }
    Start-Process powershell -Verb RunAs -ArgumentList $args
    exit
}

$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot
$log  = Join-Path $root 'install.log'
$inf  = Join-Path $root 'drivers\Saffire.inf'
$needReboot = $false

function Log($t) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $t
    $line | Out-File -FilePath $log -Append -Encoding utf8
    Write-Host $line
}

"=== INSTALL $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Out-File -FilePath $log -Append -Encoding utf8

# --- Secure Boot (informational) ---
try {
    $sb = Confirm-SecureBootUEFI -ErrorAction Stop
    Log ("Secure Boot: {0}" -f $(if ($sb) { 'enabled' } else { 'disabled' }))
} catch { Log 'Secure Boot: could not read state' }

# --- policy ---
if (-not $RepairOnly) {
    $helper = Join-Path $root 'fix-policy.ps1'
    if (Test-Path -LiteralPath $helper) {
        Log 'checking the driver policy (fix-policy.ps1)'
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$helper"
        if ($LASTEXITCODE -eq 0) { $needReboot = $true }
    } else { Log 'fix-policy.ps1 not found - skipping the policy step' }
}

# --- driver ---
$svc     = Get-Service 'Saffire' -ErrorAction SilentlyContinue
$sysFile = Join-Path $env:WINDIR 'System32\drivers\Saffire.sys'
if (($null -ne $svc) -and (Test-Path -LiteralPath $sysFile)) {
    Log 'driver already installed (service Saffire exists, files present)'
} elseif (Test-Path -LiteralPath $inf) {
    Log "installing driver from $inf"
    $out = (& pnputil.exe /add-driver "$inf" /install 2>&1 | Out-String)
    Log ($out -replace "`r`n", ' ')
    Start-Sleep -Seconds 5
    $needReboot = $true
} else {
    Log 'ERROR: driver is not installed and .\drivers\Saffire.inf is missing'
    Log 'Copy the vendor driver files into .\drivers\ first (see README).'
}

# --- device restart ---
$parent = Get-PnpDevice -ErrorAction SilentlyContinue |
    Where-Object { $_.InstanceId -like '1394\FOCUSRITE*' } | Select-Object -First 1
if ($SkipDeviceRestart) {
    Log 'device restart skipped (-SkipDeviceRestart)'
} elseif ($parent) {
    Log ("restarting device {0}" -f $parent.InstanceId)
    & pnputil.exe /disable-device "$($parent.InstanceId)" 2>&1 | Out-Null
    Start-Sleep -Seconds 3
    & pnputil.exe /enable-device "$($parent.InstanceId)" 2>&1 | Out-Null
    Start-Sleep -Seconds 6
} else {
    Log 'no device on the 1394 bus (interface connected? cable?)'
}

# --- summary ---
Log '--- state ---'
Get-PnpDevice -ErrorAction SilentlyContinue |
    Where-Object { $_.FriendlyName -match 'Saffire' } |
    ForEach-Object { Log ("  {0} | {1}/{2}" -f $_.FriendlyName, $_.Status, $_.Problem) }
foreach ($s in 'Saffire', 'SaffireAudio', 'SaffireMidi') {
    $drv = Get-CimInstance Win32_SystemDriver -Filter "Name='$s'" -ErrorAction SilentlyContinue
    if ($drv) { Log ("  service {0}: {1}" -f $s, $drv.State) }
}

if ($needReboot) { Log 'REBOOT REQUIRED. Then run verify.ps1.' }
else { Log 'Done.' }
