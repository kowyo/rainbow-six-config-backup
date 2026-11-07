[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$GameDirectory = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'My Games\Rainbow Six - Siege'),
    [string]$BackupDirectory = $PSScriptRoot
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
    throw 'Exit Rainbow Six before backing up.'
}
$source = (Resolve-Path -LiteralPath $GameDirectory).Path.TrimEnd('\')
$repository = [IO.Path]::GetFullPath($BackupDirectory).TrimEnd('\')
if ($source -eq $repository -or
    $source.StartsWith($repository + '\', [StringComparison]::OrdinalIgnoreCase) -or
    $repository.StartsWith($source + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'GameDirectory and BackupDirectory must not overlap.'
}
Assert-NoReparsePoint $source
Assert-NoReparsePoint $repository
$items = @(Get-ChildItem -LiteralPath $source -Recurse -Force)
if (@($items | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count) {
    throw 'The game directory contains a symbolic link or junction.'
}
$files = @($items | Where-Object { -not $_.PSIsContainer })
if (-not @($files | Where-Object Name -eq 'GameSettings.ini').Count) {
    throw 'No GameSettings.ini found in GameDirectory.'
}
if (-not $PSCmdlet.ShouldProcess($repository, 'Replace the international backup and manifest')) { return }

$staging = Join-Path ([IO.Path]::GetTempPath()) ('RainbowSix-Backup-' + [guid]::NewGuid().ToString('N'))
$newGame = Join-Path $staging 'NewGame'
$target = Join-Path $repository 'Rainbow Six - Siege'
$manifestPath = Join-Path $repository 'manifest.json'
New-Item -ItemType Directory -Path $newGame -Force | Out-Null
$manifest = @()
foreach ($file in $files) {
    $relative = $file.FullName.Substring($source.Length + 1)
    $copy = Join-Path $newGame $relative
    New-Item -ItemType Directory -Path (Split-Path $copy -Parent) -Force | Out-Null
    Copy-Item -LiteralPath $file.FullName -Destination $copy
    $hash = (Get-FileHash -LiteralPath $copy -Algorithm SHA256).Hash
    if ($hash -ne (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash) {
        throw "File changed during backup: $($file.FullName). Run the backup again."
    }
    $manifest += [pscustomobject]@{
        Path = 'Rainbow Six - Siege\' + $relative
        Bytes = (Get-Item -LiteralPath $copy).Length
        SHA256 = $hash
        OriginalPath = $file.FullName
        OriginalLastWriteTime = $file.LastWriteTime.ToString('o')
    }
}
$newManifest = Join-Path $staging 'NewManifest.json'
ConvertTo-Json -InputObject $manifest -Depth 4 | Set-Content -LiteralPath $newManifest -Encoding UTF8
New-Item -ItemType Directory -Path $repository -Force | Out-Null
$oldGame = Join-Path $staging 'PreviousGame'
$oldManifest = Join-Path $staging 'PreviousManifest.json'
$installedGame = $false
$installedManifest = $false
try {
    if (Test-Path -LiteralPath $target) { Move-Item -LiteralPath $target -Destination $oldGame }
    if (Test-Path -LiteralPath $manifestPath) { Move-Item -LiteralPath $manifestPath -Destination $oldManifest }
    Move-Item -LiteralPath $newGame -Destination $target
    $installedGame = $true
    Move-Item -LiteralPath $newManifest -Destination $manifestPath
    $installedManifest = $true
} catch {
    # Keep both generations recoverable if installing the new backup fails.
    if ($installedManifest) { Move-Item -LiteralPath $manifestPath -Destination (Join-Path $staging 'FailedManifest.json') }
    if ($installedGame) { Move-Item -LiteralPath $target -Destination (Join-Path $staging 'FailedGame') }
    if (Test-Path -LiteralPath $oldGame) { Move-Item -LiteralPath $oldGame -Destination $target }
    if (Test-Path -LiteralPath $oldManifest) { Move-Item -LiteralPath $oldManifest -Destination $manifestPath }
    throw
}
Write-Output "Backed up $($manifest.Count) files to $repository."
Write-Output "Previous backup, if any, retained in: $staging"
