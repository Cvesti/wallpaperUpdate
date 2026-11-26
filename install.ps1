#Requires -Version 5.1
#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'

$root = Join-Path $env:ProgramFiles 'WLLPP'
$ps = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
$files = @('DownloadWallpaper.ps1', 'ApplyWallpaper.ps1', 'ProvisionUsers.ps1')

# Проверка файлов
foreach ($file in $files) {
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $file) -PathType Leaf)) {
        throw "Не найден файл: $file"
    }
}
if ($PSScriptRoot -eq $root) {
    throw 'Запустите установщик из распакованного репозитория.'
}

# Папка установки и права доступа
New-Item -ItemType Directory -Path $root -Force | Out-Null
if ((Get-Item -LiteralPath $root -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
    throw 'Недопустимый тип папки установки.'
}
$acl = Get-Acl -LiteralPath $root
$acl.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))
$acl.SetSecurityDescriptorSddlForm('D:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;0x1200a9;;;AU)', [Security.AccessControl.AccessControlSections]::Access)
Set-Acl -LiteralPath $root -AclObject $acl

# Удаление старых задач
Get-ScheduledTask -TaskPath '\' | Where-Object {
    $_.TaskName -in @('ScheduledWLPPR_UPD','WLLPP_Wallpaper_Download','WLLPP_Wallpaper_Provision') -or
    $_.TaskName -match '^WLLPP_Wallpaper_Apply_S-1-[0-9_-]+$'
} | ForEach-Object {
    Disable-ScheduledTask -InputObject $_ | Out-Null
    Stop-ScheduledTask -InputObject $_ -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -InputObject $_ -Confirm:$false
}

# Копирование скриптов
foreach ($file in $files) {
    $destination = Join-Path $root $file
    if (Test-Path -LiteralPath $destination) {
        if ((Get-Item -LiteralPath $destination -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Недопустимый файл: $destination"
        }
        Remove-Item -LiteralPath $destination -Force
    }
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination $destination
}

# Настройки задач SYSTEM
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

# Создание задач загрузки и регистрации
foreach ($item in @(
    @{Name='Download'; File='DownloadWallpaper.ps1'; Minutes=60}
    @{Name='Provision'; File='ProvisionUsers.ps1'; Minutes=5}
)) {
    $script = Join-Path $root $item.File
    $action = New-ScheduledTaskAction -Execute $ps -Argument ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}"' -f $script)
    $repeat = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes($item.Minutes) -RepetitionInterval (New-TimeSpan -Minutes $item.Minutes) -RepetitionDuration (New-TimeSpan -Days 3650)
    $triggers = @($repeat, (New-ScheduledTaskTrigger -AtStartup))
    if ($item.Name -eq 'Provision') {
        $logon = New-ScheduledTaskTrigger -AtLogOn
        $logon.Delay = 'PT30S'
        $triggers += $logon
    }
    Register-ScheduledTask -TaskPath '\' -TaskName "WLLPP_Wallpaper_$($item.Name)" -Action $action -Trigger $triggers -Principal $principal -Settings $settings -Force | Out-Null
}

# Регистрация пользователей и первая загрузка
& $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'ProvisionUsers.ps1')
$result = $LASTEXITCODE
Start-ScheduledTask -TaskPath '\' -TaskName 'WLLPP_Wallpaper_Download'

Write-Host "Папка установки: $root"
Write-Host 'Первоначальная загрузка запущена.'
if ($result -ne 0) { exit 2 }
exit 0
