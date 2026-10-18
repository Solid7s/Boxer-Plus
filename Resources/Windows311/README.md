# Windows 3.x setup for Xcode builds

Building Boxer+ with Windows 3.x support in Xcode requires your own legally
obtained copy of Windows 3.x. Windows system files are not included in this
source repository.

Before building, place the files from your Windows 3.11 installation's C: drive
in this directory, preserving the folder structure:

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

The importer checks for `WINDOWS/WIN.COM`. It can also use an existing, closed
Windows gamebox as the source for a new game's Windows environment.

Windows system files are ignored by Git. Keep them out of source commits.
