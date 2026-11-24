@echo off
setlocal
set "INSTALL_DIR=C:\PRJ_Notification"
set "PS_SCRIPT=%INSTALL_DIR%\DownloadWallpaper.ps1"

if not exist "%PS_SCRIPT%" (
    echo [WLLPP] Не найден %PS_SCRIPT%.
    echo Сначала запустите install.ps1 от имени администратора.
    exit /b 1
)

"%WINDIR%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%PS_SCRIPT%"
set "RESULT=%ERRORLEVEL%"

if not "%RESULT%"=="0" (
    echo [WLLPP] Ошибка загрузки. Код: %RESULT%
    exit /b %RESULT%
)

exit /b 0
