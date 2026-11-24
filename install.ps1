# WLLPP Wallpaper Updater — installer
# Run this script as Administrator.

$ErrorActionPreference = "Stop"

$InstallDir = "C:\PRJ_Notification"
$BatPath = Join-Path $InstallDir "WLLPP_Update.bat"
$DownloadScript = Join-Path $InstallDir "DownloadWallpaper.ps1"
$ApplyScript = Join-Path $InstallDir "ApplyWallpaper.ps1"
$WallpaperPath = Join-Path $InstallDir "wallpaper.png"

$RepoRaw = "https://raw.githubusercontent.com/Cvesti/wallpaperUpdate/main"
$BatUrl = "$RepoRaw/WLLPP_Update.bat"
$DownloadTaskName = "WLLPP_Wallpaper_Download"
$UserTaskPrefix = "WLLPP_Wallpaper_Apply_"

function Write-Step($Message) {
    Write-Host "`n$Message" -ForegroundColor Cyan
}

# Require elevation.
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principalCheck = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principalCheck.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Запусти install.ps1 через «Запуск от имени администратора»."
}

Write-Step "1/6 Создаём папку установки..."
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

# Ensure standard users can read and execute updater files, but only SYSTEM/admins can modify them.
& icacls.exe $InstallDir /inheritance:e /grant:r "*S-1-5-18:(OI)(CI)F" "*S-1-5-32-544:(OI)(CI)F" "*S-1-5-32-545:(OI)(CI)RX" /T /C | Out-Null

Write-Step "2/6 Загружаем BAT-файл из твоего GitHub..."
$LocalBat = Join-Path $PSScriptRoot "WLLPP_Update.bat"
if (Test-Path $LocalBat) {
    Copy-Item -Path $LocalBat -Destination $BatPath -Force
} else {
    $tempBat = "$BatPath.download"
    Invoke-WebRequest -Uri $BatUrl -OutFile $tempBat -UseBasicParsing
    if (-not (Test-Path $tempBat) -or (Get-Item $tempBat).Length -lt 20) {
        throw "Не удалось найти локальный WLLPP_Update.bat и скачать его с GitHub."
    }
    Move-Item -Path $tempBat -Destination $BatPath -Force
}

Write-Step "3/6 Создаём системный загрузчик обоев..."
$downloadContent = @'
$ErrorActionPreference = "Stop"
$InstallDir = "C:\PRJ_Notification"
$WallpaperPath = Join-Path $InstallDir "wallpaper.png"
$TempPath = Join-Path $InstallDir "wallpaper.png.download"
$ImageUrl = "https://raw.githubusercontent.com/Cvesti/wallpaperUpdate/main/wallpaper.png"
$LogPath = Join-Path $InstallDir "Download.log"

function Log($Text) {
    Add-Content -Path $LogPath -Value ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Text)
}

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $ImageUrl -OutFile $TempPath -UseBasicParsing -TimeoutSec 60

    if (-not (Test-Path $TempPath)) { throw "Файл не был загружен." }
    $file = Get-Item $TempPath
    if ($file.Length -lt 8) { throw "Загруженный файл пустой или слишком маленький." }

    # Check the PNG file signature so an HTML error page is never installed as wallpaper.
    $stream = [System.IO.File]::OpenRead($TempPath)
    try {
        $signature = New-Object byte[] 8
        $read = $stream.Read($signature, 0, 8)
    } finally {
        $stream.Dispose()
    }
    $expected = [byte[]](137,80,78,71,13,10,26,10)
    $signatureHex = [BitConverter]::ToString($signature)
    $expectedHex = [BitConverter]::ToString($expected)
    if ($read -ne 8 -or $signatureHex -ne $expectedHex) {
        throw "Скачанный файл не является корректным PNG."
    }

    $newHash = (Get-FileHash -Path $TempPath -Algorithm SHA256).Hash
    $oldHash = $null
    if (Test-Path $WallpaperPath) {
        $oldHash = (Get-FileHash -Path $WallpaperPath -Algorithm SHA256).Hash
    }

    if ($newHash -ne $oldHash) {
        Move-Item -Path $TempPath -Destination $WallpaperPath -Force
        Log "Обои обновлены. SHA256: $newHash"
    } else {
        Remove-Item $TempPath -Force
        Log "Обновлений нет."
    }
} catch {
    if (Test-Path $TempPath) { Remove-Item $TempPath -Force -ErrorAction SilentlyContinue }
    Log ("ОШИБКА: " + $_.Exception.Message)
    exit 1
}
'@
Set-Content -Path $DownloadScript -Value $downloadContent -Encoding UTF8

Write-Step "4/6 Создаём скрипт применения обоев для текущего пользователя..."
$applyContent = @'
$ErrorActionPreference = "Stop"
$WallpaperPath = "C:\PRJ_Notification\wallpaper.png"
$LogPath = Join-Path $env:LOCALAPPDATA "WLLPP_Update.log"

function Log($Text) {
    try {
        Add-Content -Path $LogPath -Value ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Text)
    } catch {}
}

try {
    if (-not (Test-Path $WallpaperPath)) {
        Log "Файл обоев пока не найден."
        exit 1
    }

    # Configure wallpaper for this user's own HKCU profile.
    Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name Wallpaper -Value $WallpaperPath
    Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name WallpaperStyle -Value "10"
    Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name TileWallpaper -Value "0"

    Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class WallpaperNative {
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@

    $SPI_SETDESKWALLPAPER = 20
    $SPIF_UPDATEINIFILE = 0x01
    $SPIF_SENDCHANGE = 0x02
    $result = [WallpaperNative]::SystemParametersInfo(
        $SPI_SETDESKWALLPAPER, 0, $WallpaperPath,
        ($SPIF_UPDATEINIFILE -bor $SPIF_SENDCHANGE)
    )

    if (-not $result) {
        $code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "Windows не применил обои. Win32 error: $code"
    }

    Log "Обои применены: $WallpaperPath"
} catch {
    Log ("ОШИБКА: " + $_.Exception.Message)
    exit 1
}
'@
Set-Content -Path $ApplyScript -Value $applyContent -Encoding UTF8

Write-Step "5/6 Регистрируем задачу загрузки от SYSTEM (каждый час + при запуске Windows)..."
$downloadAction = New-ScheduledTaskAction -Execute "$env:WINDIR\System32\cmd.exe" -Argument "/c `"$BatPath`""
$hourlyDownload = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(2) `
    -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 3650)
$startupDownload = New-ScheduledTaskTrigger -AtStartup
$systemPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$downloadSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
Register-ScheduledTask -TaskName $DownloadTaskName -Action $downloadAction `
    -Trigger @($hourlyDownload, $startupDownload) -Principal $systemPrincipal `
    -Settings $downloadSettings -Description "Downloads the latest wallpaper from Cvesti/wallpaperUpdate." -Force | Out-Null

Write-Step "6/6 Создаём задачи применения обоев для всех существующих профилей Windows..."
# Existing normal user profiles only; built-in/system profiles are excluded.
$profiles = Get-CimInstance Win32_UserProfile | Where-Object {
    $_.SID -match '^S-1-5-21-' -and
    $_.LocalPath -and
    (Test-Path $_.LocalPath) -and
    -not $_.Special
}

$created = 0
foreach ($profile in $profiles) {
    $sid = $profile.SID
    $taskName = $UserTaskPrefix + ($sid -replace '[^A-Za-z0-9_-]', '_')

    $userAction = New-ScheduledTaskAction -Execute "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" `
        -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ApplyScript`""

    $userHourly = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(3) `
        -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 3650)
    $userLogon = New-ScheduledTaskTrigger -AtLogOn -User $sid
    $userPrincipal = New-ScheduledTaskPrincipal -UserId $sid -LogonType Interactive -RunLevel Limited
    $userSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 2) -MultipleInstances IgnoreNew

    Register-ScheduledTask -TaskName $taskName -Action $userAction -Trigger @($userHourly, $userLogon) `
        -Principal $userPrincipal -Settings $userSettings `
        -Description "Applies the shared GitHub wallpaper to this Windows user." -Force | Out-Null
    $created++
}

# Download now, then let each logged-on user task apply it.
Start-ScheduledTask -TaskName $DownloadTaskName
Start-Sleep -Seconds 5

# Apply immediately for users who are already signed in; others are handled at next logon.
foreach ($profile in ($profiles | Where-Object { $_.Loaded })) {
    $taskName = $UserTaskPrefix + ($profile.SID -replace '[^A-Za-z0-9_-]', '_')
    try { Start-ScheduledTask -TaskName $taskName -ErrorAction Stop } catch {
        Write-Warning "Не удалось немедленно запустить задачу для SID $($profile.SID): $($_.Exception.Message)"
    }
}

Write-Host ""
Write-Host "УСТАНОВКА ЗАВЕРШЕНА." -ForegroundColor Green
Write-Host "Папка: $InstallDir"
Write-Host "GitHub: $RepoRaw"
Write-Host "Проверка обновлений: каждый час и при запуске Windows."
Write-Host "Задач применения создано для профилей: $created"
Write-Host "Применение обоев: при входе пользователя и каждый час."
Write-Host ""
Write-Host "Лог загрузчика: $InstallDir\Download.log"
Write-Host "Лог пользователя: %LOCALAPPDATA%\WLLPP_Update.log"
Write-Host ""
Write-Host "ВАЖНО: для новых учётных записей Windows запусти этот установщик повторно от администратора."
