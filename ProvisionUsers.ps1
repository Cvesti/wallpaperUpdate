$ErrorActionPreference = 'Stop'

$script = Join-Path $PSScriptRoot 'ApplyWallpaper.ps1'
$logFile = Join-Path $PSScriptRoot 'Provision.log'
$ps = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
$failed = $false

function Log($message) {
    Add-Content -LiteralPath $logFile -Encoding UTF8 -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $message"
}

# Поиск профилей
$profiles = @(Get-CimInstance Win32_UserProfile | Where-Object {
    -not $_.Special -and $_.SID -match '^S-1-(5-21|12-1)-'
})

foreach ($profile in $profiles) {
    $sid = $profile.SID
    $name = "WLLPP_Wallpaper_Apply_$sid"

    # Проверка существующей задачи
    if (Get-ScheduledTask -TaskPath '\' -TaskName $name -ErrorAction SilentlyContinue) {
        continue
    }

    try {
        # Имя пользователя по SID
        $user = $sid
        try {
            $user = ([Security.Principal.SecurityIdentifier]::new($sid)).Translate([Security.Principal.NTAccount]).Value
        } catch { }

        $action = New-ScheduledTaskAction -Execute $ps -Argument ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $script)

        # Расписание применения
        $repeat = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 3650)
        $logon = New-ScheduledTaskTrigger -AtLogOn -User $user
        $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 3)

        Register-ScheduledTask -TaskPath '\' -TaskName $name -Action $action -Trigger @($repeat, $logon) -Principal $principal -Settings $settings -Force | Out-Null
        Log "Создана задача для пользователя: $user"

        # Запуск для вошедшего пользователя
        if ($profile.Loaded) {
            Start-ScheduledTask -TaskPath '\' -TaskName $name
        }
    } catch {
        $failed = $true
        Log "ОШИБКА регистрации $($sid): $($_.Exception.Message)"
    }
}

# Удаление задач старых профилей
$existing = @($profiles | ForEach-Object { "WLLPP_Wallpaper_Apply_$($_.SID)" })
Get-ScheduledTask -TaskPath '\' -TaskName 'WLLPP_Wallpaper_Apply_*' -ErrorAction SilentlyContinue |
    Where-Object {
        $_.TaskName -match '^WLLPP_Wallpaper_Apply_S-1-[0-9-]+$' -and $_.TaskName -notin $existing
    } | Unregister-ScheduledTask -Confirm:$false

if ($failed) { exit 1 }
exit 0
