# Windows 3.11 runtime files

For a source build with automatic Windows setup, place your Windows 3.11 C-drive files here:

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

Xcode includes this folder in the app resources. The importer reads `Boxer+.app/Contents/Resources/Windows311` and copies its contents into the new gamebox. Once compiled, the app does not need the project folder.

The v1.1.0 app release includes the local template. Windows system binaries are excluded from this source repository; builds without them offer an existing Windows gamebox as a fallback.
