# Custom Desktop Wallpaper

Place your custom desktop background image here as **`wallpaper.jpg`** (or update `"CustomWallpaperPath"` in `config.json`).

During ISO creation, `Build-TinyWin11.ps1` will:
1. Copy your image into `C:\Windows\Web\Wallpaper\Windows\tinywin_wallpaper.jpg`.
2. Replace the default Windows 11 Light (`img0.jpg`) and Dark (`img19.jpg`) wallpapers inside the WIM image.
3. Configure the Default User registry hive and `FirstLogon.ps1` so all accounts automatically boot into your custom background.
