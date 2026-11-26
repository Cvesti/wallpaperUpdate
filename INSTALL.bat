@echo off
chcp 65001 >nul
setlocal EnableExtensions DisableDelayedExpansion
title WLLPP Wallpaper Updater

REM Путь к установщику
set "INSTALL_SCRIPT=%~dp0install.ps1"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

if not exist "%INSTALL_SCRIPT%" (
    echo Файл install.ps1 не найден.
    pause
    exit /b 1
)

REM Запуск от администратора
"%PS%" -NoProfile -Command "try { $p = Start-Process -FilePath $env:PS -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File ' + [char]34 + $env:INSTALL_SCRIPT + [char]34) -Verb RunAs -Wait -PassThru -ErrorAction Stop; exit $p.ExitCode } catch { Write-Host $_.Exception.Message; exit 1 }"

set "RESULT=%ERRORLEVEL%"
echo.
if "%RESULT%"=="0" (
    echo Установка завершена. Загрузка обоев запущена.
) else if "%RESULT%"=="2" (
    echo Установка завершена с предупреждениями.
) else (
    echo Ошибка установки: %RESULT%
)
pause
exit /b %RESULT%
