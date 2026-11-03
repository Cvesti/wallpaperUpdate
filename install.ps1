# Запускать ОТ ИМЕНИ АДМИНИСТРАТОРА

$InstallDir = "C:\PRJ_Notification"
$BatScript = Join-Path $InstallDir "WLLPP_Update.bat"
$ImgPath = Join-Path $InstallDir "wallpaper.png"

Write-Host "1. Папочка создается $InstallDir..." -ForegroundColor Cyan
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

Write-Host "2. Скачиваем скрипт с гита" -ForegroundColor Cyan
$BatUrl = "https://raw.githubusercontent.com/Cvesti/wallpaperUpdate/main/WLLPP_Update.bat"
Invoke-WebRequest -Uri $BatUrl -OutFile $BatScript -UseBasicParsing

Write-Host "3. Скачиваем картинку с GitHub..." -ForegroundColor Cyan
$ImgUrl = "https://raw.githubusercontent.com/Cvesti/wallpaperUpdate/main/wallpaper.png"
Invoke-WebRequest -Uri $ImgUrl -OutFile $ImgPath -UseBasicParsing

Write-Host "4. Удаляем старую задачу" -ForegroundColor Cyan
schtasks /Delete /TN "ScheduledWLPPR_UPD" /F 2>$null | Out-Null

Write-Host "5. Создаем новую задачу от имени БОГОПОДОБНОЙ СИСТЕМЫ" -ForegroundColor Cyan
$action  = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c `"$BatScript`""
$trigger = New-ScheduledTaskTrigger -Daily -At "19:25"
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

Register-ScheduledTask -TaskName "ScheduledWLPPR_UPD" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null

Write-Host "6. Проверяем" -ForegroundColor Cyan
Start-ScheduledTask -TaskName "ScheduledWLPPR_UPD"
Start-Sleep -Seconds 3

Write-Host "`n✅ ГОТОВО! Началось удаление всего с вашего персонального компьютера" -ForegroundColor Green
Write-Host "Обои должны обновиться в течение нескольких секунд." -ForegroundColor Green
Write-Host "В дальнейшем обои будут обновляться каждый день в 19:25." -ForegroundColor Green