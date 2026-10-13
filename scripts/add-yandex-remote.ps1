# Подключает Яндекс Диск к rclone по токену Полигона (Windows PowerShell 5.1+ и PowerShell 7).
#
#   powershell -ExecutionPolicy Bypass -File .\add-yandex-remote.ps1 [-Name yandex]
#
# Токен берётся на https://yandex.ru/dev/disk/poligon/ (кнопка «Получить OAuth-токен»).
# Почему так, а не через `rclone config`: приложению rclone Яндекс сейчас отвечает 410 GoneError
# на любые файлы. Секция пишется в rclone.conf напрямую, а не аргументом командной строки:
# Windows PowerShell 5.1 портит кавычки в JSON, передаваемом внешним программам.
param([string]$Name = "yandex")
$ErrorActionPreference = "Stop"

if (-not (Get-Command rclone -ErrorAction SilentlyContinue)) {
    Write-Host "rclone не найден. Установите: winget install Rclone.Rclone  — и откройте PowerShell заново." -ForegroundColor Red
    exit 1
}

$conf = (rclone config file | Select-Object -Last 1).Trim()
if ((Test-Path $conf) -and (Select-String -Path $conf -Pattern "^\[$([regex]::Escape($Name))\]" -Quiet)) {
    Write-Host "Подключение [$Name] уже есть в $conf. Выберите другое имя: -Name yandex2" -ForegroundColor Yellow
    exit 1
}

$secure = Read-Host "Вставьте токен Полигона (ввод не отображается)" -AsSecureString
$token = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)).Trim()
if ($token -notmatch '^[A-Za-z0-9_\-\.]{20,}$') {
    Write-Host "Это не похоже на токен Полигона (ожидается одна строка из букв, цифр, - и _)." -ForegroundColor Red
    exit 1
}

# refresh_token — заглушка: без него rclone не стартует; expiry в будущем, чтобы rclone не пытался обновлять токен.
$section = "`r`n[$Name]`r`ntype = yandex`r`ntoken = {""access_token"":""$token"",""token_type"":""OAuth"",""refresh_token"":""unused"",""expiry"":""2099-01-01T00:00:00Z""}`r`n"
New-Item -ItemType Directory -Force -Path (Split-Path $conf) | Out-Null
Add-Content -Path $conf -Value $section -Encoding ascii   # ascii: без BOM, rclone его не любит

Write-Host "Проверяю доступ..."
rclone about "${Name}:"
if ($LASTEXITCODE -ne 0) {
    Write-Host "Не получилось. Токен истёк или скопирован не полностью. Удалите секцию [$Name] из $conf и повторите." -ForegroundColor Red
    exit 1
}
Write-Host "Готово: подключение [$Name] записано в $conf" -ForegroundColor Green
