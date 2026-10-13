# Windows: Яндекс Диск → внешний диск

Пошагово, для тех, кто первый раз открывает PowerShell. Около 10 минут на настройку, дальше копирование
идёт само.

[← назад к README](../README.md)

## 0. Что понадобится

- Windows 10 или 11.
- Диск с местом не меньше, чем занято на Яндекс Диске. Сколько занято, видно внизу слева
  на [disk.yandex.ru](https://disk.yandex.ru) или командой `rclone about yandex:` после шага 3.
- Фото из «безлимита» в этот объём не входят и rclone их не видит, о них [отдельно](unlimited-photos.md).

## 1. Откройте PowerShell

Нажмите **Win**, наберите `PowerShell`, нажмите **Enter**. Все команды ниже вставляются туда
правой кнопкой мыши или Ctrl+V и запускаются Enter.

Перейдите в папку, где будут лежать скрипты и логи, например в «Документы»:
```powershell
cd $HOME\Documents
```

## 2. Установите rclone

```powershell
winget install Rclone.Rclone
```

Закройте PowerShell и откройте снова (шаг 1), иначе Windows не найдёт команду. Проверка:
```powershell
rclone version
```
Должна быть версия 1.75 или новее. Если `winget` нет: скачайте zip с [rclone.org/downloads](https://rclone.org/downloads/),
распакуйте, например, в `C:\rclone` и запускайте как `C:\rclone\rclone.exe`.

## 3. Подключите Яндекс Диск

1. Откройте [Полигон Яндекс Диска](https://yandex.ru/dev/disk/poligon/), войдите в **тот** аккаунт,
   который спасаете, и нажмите **«Получить OAuth-токен»**. Скопируйте длинную строку.
2. Скачайте и запустите скрипт подключения:
   ```powershell
   irm https://raw.githubusercontent.com/KenGuru66/yandex-disk-rescue/main/scripts/add-yandex-remote.ps1 -OutFile add-yandex-remote.ps1
   powershell -ExecutionPolicy Bypass -File .\add-yandex-remote.ps1
   ```
3. Вставьте токен, когда скрипт попросит (символы не отображаются, это нормально), и нажмите Enter.
   В конце скрипт покажет `Total`, `Used`, `Free` вашего Диска. Значит, всё работает.

Зачем Полигон, а не обычная настройка rclone: приложению rclone Яндекс сейчас отвечает `410 GoneError`.
Подробности — в [how-it-works.md](how-it-works.md#почему-токен-полигона).

> [!WARNING]
> Токен Полигона даёт **полный** доступ к вашему Диску. Он хранится в файле конфигурации rclone
> (`rclone config file` покажет путь). Не отправляйте этот файл и токен никому, включая авторов этого проекта.

## 4. Копируйте

```powershell
irm https://raw.githubusercontent.com/KenGuru66/yandex-disk-rescue/main/scripts/backup.ps1 -OutFile backup.ps1
powershell -ExecutionPolicy Bypass -File .\backup.ps1 -Dest E:\YandexDisk
```

- `E:\YandexDisk` — куда сохранять. Папка создастся сама.
- Только часть Диска: `-Source "yandex:Документы"`.
- Больше потоков на быстром канале: `-Transfers 32`.

На экране идёт прогресс. Окно можно свернуть, но не закрывайте его и не давайте компьютеру уснуть
(«Параметры → Система → Питание»).

В конце скрипт напишет, сколько скопировано и сколько нет. Несохранённые файлы перечислены
в `yandex-rescue-<дата>-failed.txt`. Сейчас это в основном файлы, которые Яндекс временно не отдаёт.

## 5. Повторяйте

Запускайте ту же команду раз в день или после новостей о восстановлении Яндекса. Повторный запуск
пропускает уже скопированное и пробует только недостающее.

Автоматически каждый день в 3:00 (одна команда, PowerShell от вашего пользователя):
```powershell
$a = "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PWD\backup.ps1`" -Dest E:\YandexDisk"
Register-ScheduledTask -TaskName "yandex-disk-rescue" -Trigger (New-ScheduledTaskTrigger -Daily -At 3am) `
  -Action (New-ScheduledTaskAction -Execute powershell.exe -Argument $a -WorkingDirectory $PWD)
```
Удалить задание: `Unregister-ScheduledTask yandex-disk-rescue -Confirm:$false`.

## 6. Проверьте копию

```powershell
rclone check yandex: E:\YandexDisk --one-way --missing-on-dst missing.txt --differ differ.txt
```
rclone сравнит каждый файл по MD5. `missing.txt` — чего ещё нет в копии, `differ.txt` — что отличается
(должен быть пустым). Проверка читает всю локальную копию, на терабайте это займёт время.

## 7. Когда всё скопировано — отзовите токен

См. [troubleshooting → как отозвать токен](troubleshooting.md#как-отозвать-токен).

## Вручную, без скриптов

Если не хотите запускать скачанные скрипты, всё то же самое делается командами.

Подключение: дописываем секцию в конфиг rclone (вместо `ТОКЕН` вставьте токен Полигона):
```powershell
$conf = (rclone config file | Select-Object -Last 1).Trim()
New-Item -ItemType Directory -Force (Split-Path $conf) | Out-Null
Add-Content -Encoding ascii $conf "`r`n[yandex]`r`ntype = yandex`r`ntoken = {""access_token"":""ТОКЕН"",""token_type"":""OAuth"",""refresh_token"":""unused"",""expiry"":""2099-01-01T00:00:00Z""}`r`n"
rclone about yandex:
```

Копирование:
```powershell
rclone copy yandex: E:\YandexDisk --transfers 16 --checkers 8 --timeout 60s --contimeout 15s `
  --low-level-retries 2 --retries 1 --progress --log-file rescue.log --log-level INFO
```
Список несохранённого: `Select-String " ERROR : " rescue.log`.

[← назад к README](../README.md)
