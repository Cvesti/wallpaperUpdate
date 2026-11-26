$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$url = 'https://raw.githubusercontent.com/Cvesti/wallpaperUpdate/main/wallpaper.png'
$target = Join-Path $PSScriptRoot 'wallpaper.bmp'
$hashFile = Join-Path $PSScriptRoot 'wallpaper.sha256'
$temp = Join-Path $PSScriptRoot 'download.tmp'
$tempBmp = Join-Path $PSScriptRoot 'wallpaper.tmp'
$logFile = Join-Path $PSScriptRoot 'Download.log'

function Log($message) {
    Add-Content -LiteralPath $logFile -Encoding UTF8 -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $message"
}

$failed = $false

# Регистрация новых пользователей
try {
    $ps = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
    & $ps -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'ProvisionUsers.ps1')
    if ($LASTEXITCODE -ne 0) {
        $failed = $true
        Log 'Не все профили удалось зарегистрировать.'
    }
} catch {
    $failed = $true
    Log "Ошибка регистрации: $($_.Exception.Message)"
}

try {
    # Скачивание обоев
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $url -OutFile $temp -UseBasicParsing -TimeoutSec 90 -Headers @{'Cache-Control'='no-cache'}
    if ((Get-Item -LiteralPath $temp).Length -gt 30MB) {
        throw 'Изображение превышает 30 МБ.'
    }

    # Проверка изменений
    $hash = (Get-FileHash -LiteralPath $temp -Algorithm SHA256).Hash
    $oldHash = ''
    if (Test-Path -LiteralPath $hashFile) {
        $oldHash = (Get-Content -LiteralPath $hashFile -Raw).Trim()
    }

    if ($hash -ne $oldHash -or -not (Test-Path -LiteralPath $target)) {
        # Проверка PNG и перевод в BMP
        Add-Type -AssemblyName PresentationCore
        $inputStream = [IO.File]::OpenRead($temp)
        try {
            $decoder = [Windows.Media.Imaging.BitmapDecoder]::Create(
                $inputStream,
                [Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat,
                [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            )
            if ($decoder -isnot [Windows.Media.Imaging.PngBitmapDecoder]) {
                throw 'Скачанный файл не является PNG.'
            }
            $frame = $decoder.Frames[0]
            if ([long]$frame.PixelWidth * $frame.PixelHeight -gt 40000000) {
                throw 'Слишком большое разрешение изображения.'
            }
            $rgb = [Windows.Media.Imaging.FormatConvertedBitmap]::new(
                $frame, [Windows.Media.PixelFormats]::Bgr24, $null, 0
            )
            $encoder = New-Object Windows.Media.Imaging.BmpBitmapEncoder
            $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($rgb))
            $output = [IO.File]::Create($tempBmp)
            try { $encoder.Save($output) } finally { $output.Dispose() }
        } finally {
            $inputStream.Dispose()
        }

        # Сброс старого хеша
        if (Test-Path -LiteralPath $hashFile) {
            Remove-Item -LiteralPath $hashFile -Force
        }
        # Замена изображения
        if (Test-Path -LiteralPath $target) {
            [IO.File]::Replace($tempBmp, $target, [System.Management.Automation.Language.NullString]::Value)
        } else {
            [IO.File]::Move($tempBmp, $target)
        }
        Set-Content -LiteralPath $hashFile -Value $hash -Encoding ASCII
        Log "Обои обновлены. SHA256: $hash"
    } else {
        Log 'Обновлений нет.'
    }

} catch {
    $failed = $true
    Log "ОШИБКА: $($_.Exception.Message)"
} finally {
    Remove-Item -LiteralPath $temp, $tempBmp -Force -ErrorAction SilentlyContinue
}

# Применение обоев
if (Test-Path -LiteralPath $target) {
    try {
        Get-CimInstance Win32_UserProfile | Where-Object {
            $_.Loaded -and -not $_.Special -and $_.SID -match '^S-1-(5-21|12-1)-'
        } | ForEach-Object {
            $task = "WLLPP_Wallpaper_Apply_$($_.SID)"
            try {
                Start-ScheduledTask -TaskPath '\' -TaskName $task
                Log "Запрошено применение: $task"
            } catch {
                Log "Не удалось запустить $($task): $($_.Exception.Message)"
            }
        }
    } catch {
        $failed = $true
        Log "Ошибка запуска задач: $($_.Exception.Message)"
    }
}

if ($failed) { exit 1 }
exit 0
