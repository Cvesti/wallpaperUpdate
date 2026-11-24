@echo off
chcp 65001 >nul
setlocal EnableExtensions

set "REPO_RAW=https://raw.githubusercontent.com/Cvesti/wallpaperUpdate/main"
set "SELF=%~f0"
set "HERE=%~dp0"
set "PS1=%HERE%install.ps1"

REM --- Проверка прав администратора ---
net session >nul 2>&1
if errorlevel 1 (
    echo [WLLPP] Требуются права администратора.
    echo [WLLPP] Запрашиваем UAC...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath $env:SELF -Verb RunAs"
    exit /b
)

echo [WLLPP] Установка обновлятора обоев WLLPP
echo.

REM --- Убеждаемся, что install.ps1 есть локально ---
if not exist "%PS1%" (
    echo [WLLPP] install.ps1 не найден рядом с INSTALL.bat.
    echo [WLLPP] Пробуем скачать с GitHub...
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
        "$ErrorActionPreference='Stop'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%REPO_RAW%/install.ps1' -OutFile '%PS1%' -UseBasicParsing"
    if not exist "%PS1%" (
        echo [WLLPP] ОШИБКА: не удалось получить install.ps1.
        pause
        exit /b 1
    )
)

echo [WLLPP] Запускаем install.ps1...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
set "RESULT=%ERRORLEVEL%"

echo.
if not "%RESULT%"=="0" (
    echo [WLLPP] Установка завершилась с ошибкой. Код: %RESULT%
    pause
    exit /b %RESULT%
)

echo [WLLPP] Установка успешно завершена.
pause
exit /b 0