# Windows 3.11 Files

Boxer-Plus can use this folder as a local Windows 3.11 runtime when importing Windows 3.x games.

The actual Windows 3.11 system files are not included in this repository because they are proprietary Microsoft files. To use the Windows 3.11 installer flow, place files from your own legally obtained Windows 3.11 installation here.

Expected layout:

```text
Resources/Windows311/
  AUTOEXEC.BAT
  CONFIG.SYS
  WINDOWS/
    WIN.COM
    ...
  SB16/
    ...
```

At build time, `Scripts/CopyWindows311.sh` copies this folder into the app bundle resources when the files are present locally.
