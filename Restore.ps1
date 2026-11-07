[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$GameDirectory = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'My Games\Rainbow Six - Siege'),
    [string]$BackupDirectory = $PSScriptRoot,
    [string]$AccountId
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-NoReparsePoint([string]$Path) {
    while ($Path) {
        if ((Test-Path -LiteralPath $Path) -and
            ((Get-Item -LiteralPath $Path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Symbolic links and junctions are not supported: $Path"
        }
        $Path = [IO.Path]::GetDirectoryName($Path)
    }
}

if (Get-Process -ErrorAction SilentlyContinue | Where-Object ProcessName -like 'RainbowSix*') {
    throw 'Exit Rainbow Six before restoring.'
}
$repository = (Resolve-Path -LiteralPath $BackupDirectory).Path.TrimEnd('\')
$source = Join-Path $repository 'Rainbow Six - Siege'
$destination = [IO.Path]::GetFullPath($GameDirectory).TrimEnd('\')
if ($destination -eq $repository -or
    $destination.StartsWith($repository + '\', [StringComparison]::OrdinalIgnoreCase) -or
    $repository.StartsWith($destination + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'GameDirectory and BackupDirectory must not overlap.'
}
Assert-NoReparsePoint $repository
Assert-NoReparsePoint $destination
Assert-NoReparsePoint (Join-Path $repository 'manifest.json')
$manifest = Get-Content -LiteralPath (Join-Path $repository 'manifest.json') -Raw | ConvertFrom-Json
$manifest = @($manifest)
$plan = @()
$seen = @{}
foreach ($entry in $manifest) {
    # Restore account configuration only; benchmark reports are historical data.
    if ($entry.Path -notmatch '^Rainbow Six - Siege\\([^\\/]+)\\GameSettings\.ini$') { continue }
    $account = $Matches[1]
    if ($account -in @('.', '..') -or $account.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
        throw "Invalid account directory in manifest: $account"
    }
    if ($AccountId -and $account -ne $AccountId) { continue }
    if ($seen.ContainsKey($account)) { throw "Duplicate account in manifest: $account" }
    $seen[$account] = $true
    $relative = Join-Path $account 'GameSettings.ini'
    $inputFile = Join-Path $source $relative
    $outputFile = Join-Path $destination $relative
    Assert-NoReparsePoint $inputFile
    Assert-NoReparsePoint $outputFile
    if ((Get-FileHash -LiteralPath $inputFile -Algorithm SHA256).Hash -ne $entry.SHA256 -or
        (Get-Item -LiteralPath $inputFile).Length -ne $entry.Bytes) {
        throw "Backup integrity check failed: $inputFile"
    }
    $plan += [pscustomobject]@{ Source=$inputFile; Target=$outputFile; Relative=$relative; Hash=$entry.SHA256; Existed=(Test-Path -LiteralPath $outputFile) }
}
if (-not $plan.Count) { throw 'No matching account configurations found in manifest.json.' }
if (-not $PSCmdlet.ShouldProcess($destination, "Restore $($plan.Count) account configuration(s)")) { return }

$safety = Join-Path ([IO.Path]::GetTempPath()) ('RainbowSix-BeforeRestore-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $safety | Out-Null
# Save every file that will be replaced before writing any game configuration.
foreach ($item in $plan) {
    if ($item.Existed) {
        $saved = Join-Path $safety $item.Relative
        New-Item -ItemType Directory -Path (Split-Path $saved -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $item.Target -Destination $saved
        if ((Get-FileHash -LiteralPath $saved).Hash -ne (Get-FileHash -LiteralPath $item.Target).Hash) {
            throw 'Current configuration changed while saving the safety copy. Run restore again.'
        }
    }
}
$written = @()
try {
    foreach ($item in $plan) {
        New-Item -ItemType Directory -Path (Split-Path $item.Target -Parent) -Force | Out-Null
        $written += $item
        Copy-Item -LiteralPath $item.Source -Destination $item.Target -Force
        if ((Get-FileHash -LiteralPath $item.Target -Algorithm SHA256).Hash -ne $item.Hash) {
            throw "Restored file integrity check failed: $($item.Target)"
        }
    }
} catch {
    foreach ($item in $written) {
        if ($item.Existed) {
            Copy-Item -LiteralPath (Join-Path $safety $item.Relative) -Destination $item.Target -Force
        } elseif (Test-Path -LiteralPath $item.Target) {
            Remove-Item -LiteralPath $item.Target
        }
    }
    throw
}
Write-Output "Restored $($plan.Count) account configuration(s) to $destination."
Write-Output "Previous configuration files, if any, retained in: $safety"
