# Rainbow Six Siege International Configuration Backup

Initial backup captured on November 5, 2026 at 23:42:31 (UTC+08:00).

## Contents

The international edition configuration files are stored directly in `Rainbow Six - Siege/`, preserving their original account directory names. The backup contains two `GameSettings.ini` files and historical benchmark results.

`manifest.json` records each original file's full path, size, modification time, and SHA-256 checksum. `.gitattributes` prevents Git from changing line endings, preserving the backup bytes.

## Backup

Exit the game, open PowerShell in this repository, and run:

```powershell
.\Backup.ps1
```

The script copies the international edition directory from your Windows Documents folder, verifies every copied file, and replaces `Rainbow Six - Siege/` and `manifest.json`. Files absent from the new backup are removed from the repository snapshot. The previous snapshot is retained in a temporary recovery directory; the script prints its path. Your live game files are unchanged.

For a custom installation or a preview:

```powershell
.\Backup.ps1 -GameDirectory 'D:\My Games\Rainbow Six - Siege'
.\Backup.ps1 -WhatIf
```

## Restore

Exit the game and run:

```powershell
.\Restore.ps1 -WhatIf
.\Restore.ps1
```

The script verifies the selected backup files before writing, saves the current files in a temporary recovery directory, and restores the account `GameSettings.ini` files. It prints the recovery directory and rolls back files if restoration fails. Benchmark reports are not restored.

By default, all backed-up accounts are restored to their original account directory names under your current Windows Documents folder. `OriginalPath` in the manifest is informational; paths from another computer are not used as restore destinations. To select one account or a custom destination:

```powershell
.\Restore.ps1 -AccountId '2c10a7b7-1685-43ba-9bfc-4b367cb414ff'
.\Restore.ps1 -GameDirectory 'D:\My Games\Rainbow Six - Siege'
```

Both scripts support Windows PowerShell 5.1 and PowerShell 7. `-BackupDirectory` selects an alternative repository folder. Neither script creates commits or uploads files. To publish a refreshed backup while keeping one commit:

```powershell
git add -- 'Rainbow Six - Siege' manifest.json
git commit --amend --no-edit
git push --force-with-lease origin main
```

This backup covers the local international edition configuration directory only. It does not include launcher saves stored elsewhere or cloud data.

## Verify a file

Run the following in PowerShell, replacing the example path with the file you want to check, and compare the result with its SHA256 value in `manifest.json`:

```powershell
(Get-FileHash -LiteralPath '.\path\to\GameSettings.ini' -Algorithm SHA256).Hash
```
