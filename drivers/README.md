# Offline Drivers

Drop signed `.inf` driver packs here (one sub-folder per pack). `Build-TinyWin11.ps1` injects every pack found in this folder into the `install.wim` DriverStore, and `drivers/VirtIO/` into `boot.wim` for Windows Setup.

Driver binaries are not tracked in git (multi-GB vendor packages). Expected layout:

```
drivers/
  VirtIO/            # Windows 11 x64 VirtIO drivers (viostor, vioscsi, NetKVM, vioinput, viogpudo, ...)
  Intel_POS_Common/  # Intel Chipset, UHD Graphics, CSME, Serial IO
  CQ-JY12-N150/      # N150 POS terminal OEM driver pack
```

Folder names are configurable in `config.json` under `"Drivers"` (`DriversRootFolder`, `VirtIOFolder`).
