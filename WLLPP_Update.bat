@echo off
curl -s -o C:\PRJ_Notification\wallpaper.png "https://raw.githubusercontent.com/Cvesti/wallpaperUpdate/main/wallpaper.png"

for /f "tokens=*" %%a in ('dir /b /a:d "C:\Users"') do (
    if exist "C:\Users\%%a\NTUSER.DAT" (
        reg load "HKU\TempHive_%%a" "C:\Users\%%a\NTUSER.DAT" >nul 2>&1
        if errorlevel 0 (
            reg add "HKU\TempHive_%%a\Control Panel\Desktop" /v Wallpaper /t REG_SZ /d "C:\PRJ_Notification\wallpaper.png" /f >nul
            reg add "HKU\TempHive_%%a\Control Panel\Desktop" /v WallpaperStyle /t REG_SZ /d "10" /f >nul
            reg add "HKU\TempHive_%%a\Control Panel\Desktop" /v TileWallpaper /t REG_SZ /d "0" /f >nul
            reg unload "HKU\TempHive_%%a" >nul 2>&1
        )
    )
)

    
RUNDLL32.EXE user32.dll,UpdatePerUserSystemParameters