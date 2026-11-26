$ErrorActionPreference = 'Stop'

$source = Join-Path $PSScriptRoot 'wallpaper.bmp'
$cache = Join-Path $env:LOCALAPPDATA 'WLLPP'
$logFile = Join-Path $env:LOCALAPPDATA 'WLLPP_Update.log'
$desktop = 'HKCU:\Control Panel\Desktop'
$temp = $null

function Log($message) {
    Add-Content -LiteralPath $logFile -Encoding UTF8 -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $message"
}

try {
    # Проверка сеанса
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $session = [Diagnostics.Process]::GetCurrentProcess().SessionId
    if ($identity.IsSystem -or $session -eq 0) {
        throw 'Требуется интерактивный пользовательский сеанс.'
    }
    if (-not (Test-Path -LiteralPath $source)) { exit 0 }

    New-Item -ItemType Directory -Path $cache -Force | Out-Null

    # Чтение изображения
    $stream = [IO.File]::Open($source, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::Read -bor [IO.FileShare]::Delete))
    try {
        # Имя файла по хешу
        $sha = [Security.Cryptography.SHA256]::Create()
        try {
            $hash = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '')
        } finally { $sha.Dispose() }

        $target = Join-Path $cache "wallpaper_$hash.bmp"
        $current = Get-ItemProperty -LiteralPath $desktop

        # Проверка текущих обоев
        if ((Test-Path -LiteralPath $target) -and
            $current.Wallpaper -eq $target -and
            $current.WallpaperStyle -eq '10' -and
            $current.TileWallpaper -eq '0') {
            exit 0
        }
        if (-not (Test-Path -LiteralPath $target)) {
            $stream.Position = 0
            $temp = Join-Path $cache "$([Guid]::NewGuid()).tmp"
            $output = [IO.File]::Create($temp)
            try { $stream.CopyTo($output) } finally { $output.Dispose() }
            Move-Item -LiteralPath $temp -Destination $target -Force
        }
    } finally { $stream.Dispose() }

    # Функция Windows для смены обоев
    if (-not ('Wallpaper' -as [type])) {
        Add-Type @"
using System.Runtime.InteropServices;
public class Wallpaper {
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool SystemParametersInfo(
        int action, int param, string path, int flags
    );
}
"@
    }
    # Режим заполнения
    Set-ItemProperty -LiteralPath $desktop -Name WallpaperStyle -Value '10'
    Set-ItemProperty -LiteralPath $desktop -Name TileWallpaper -Value '0'

    if (-not [Wallpaper]::SystemParametersInfo(20, 0, $target, 3)) {
        throw "Ошибка Windows API: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
    }
    Log "Обои применены. Пользователь: $($identity.Name); сеанс: $session; SHA256: $hash"

    # Удаление старых копий
    Get-ChildItem -LiteralPath $cache -Filter 'wallpaper_*.bmp' -File |
        Where-Object {
            $_.Name -match '^wallpaper_[0-9A-F]{64}\.bmp$' -and $_.FullName -ne $target
        } | Remove-Item -Force -ErrorAction SilentlyContinue
    exit 0
} catch {
    Log "ОШИБКА: $($_.Exception.Message)"
    exit 1
} finally {
    if ($temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
}
