# Копирует Яндекс Диск в папку или облако. Только copy: в месте назначения ничего не удаляется.
# Повторный запуск докачивает то, что не скопировалось (в т. ч. файлы, которые Яндекс вернёт позже).
#
#   powershell -ExecutionPolicy Bypass -File .\backup.ps1 -Dest E:\YandexDisk
#   powershell -ExecutionPolicy Bypass -File .\backup.ps1 -Dest gdrive:Yandex-backup -Source "yandex:Документы"
#
# Лог и список неудачных файлов кладутся в текущую папку.
param(
    [Parameter(Mandatory = $true)][string]$Dest,
    [string]$Source = "yandex:",
    [int]$Transfers = 16
)
$ErrorActionPreference = "Stop"
if (-not (Get-Command rclone -ErrorAction SilentlyContinue)) {
    Write-Host "rclone не найден. Установите: winget install Rclone.Rclone" -ForegroundColor Red; exit 1
}

$stamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
$log = Join-Path (Get-Location) "yandex-rescue-$stamp.log"
$failed = Join-Path (Get-Location) "yandex-rescue-$stamp-failed.txt"

$rcArgs = @(
    "copy", $Source, $Dest,
    "--transfers", $Transfers, "--checkers", "8",
    # Яндекс сейчас долго выдаёт ссылки и часть файлов не отдаёт совсем: ждём минуту, повторяем один раз
    "--timeout", "60s", "--contimeout", "15s", "--low-level-retries", "2", "--retries", "1",
    "--progress", "--stats", "30s",
    "--log-file", $log, "--log-level", "INFO"
)
# Облако (gdrive:..., s3:...) — сравнение по MD5; буква диска (E:\...) — по размеру и дате
if ($Dest -match '^[A-Za-z][A-Za-z0-9_\-]+:') { $rcArgs += "--checksum" }

Write-Host "Копирую $Source -> $Dest. Лог: $log"
& rclone @rcArgs
$code = $LASTEXITCODE

$errs = Select-String -Path $log -Pattern ' ERROR : (.+?): Failed to copy' -AllMatches |
        ForEach-Object { $_.Matches[0].Groups[1].Value } | Sort-Object -Unique
$errs | Set-Content -Path $failed -Encoding utf8
$copied = (Select-String -Path $log -Pattern 'Copied \(' -SimpleMatch:$false).Count

Write-Host ""
Write-Host "Скопировано файлов: $copied"
if ($errs.Count -gt 0) {
    Write-Host "Не скопировано: $($errs.Count) (список: $failed)" -ForegroundColor Yellow
    Write-Host "Обычно это файлы, которые Яндекс сейчас не отдаёт. Запустите этот же скрипт позже — он докачает только недостающее."
} elseif ($code -eq 0) {
    Write-Host "Ошибок нет." -ForegroundColor Green
} else {
    Write-Host "rclone завершился с ошибкой (код $code). Последние строки лога:" -ForegroundColor Red
    Get-Content $log -Tail 5 | ForEach-Object { Write-Host "  $_" }
}
exit $code
