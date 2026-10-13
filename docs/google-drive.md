# Яндекс Диск → Google Drive

Копия в другом облаке и другой юрисдикции. Файлы идут из Яндекса в Google через ваш компьютер или сервер,
место на локальном диске не нужно.

[← назад к README](../README.md)

## Перед началом

- **Место в Google.** Бесплатно 15 ГБ (вместе с Gmail и Google Фото). Для большого Диска нужен Google One:
  2 ТБ — около $10 в месяц. Из России Google One картой российского банка не оплатить.
- **Лимит загрузки Google — 750 ГБ в сутки.** Больше за день не залить; rclone остановится сам
  (`--drive-stop-on-upload-limit`), а следующий запуск продолжит.
- **Яндекс уже подключён** к rclone как `yandex:` (шаги 1–3 из [windows.md](windows.md) или [linux-macos.md](linux-macos.md)).

## 1. Свой client_id Google (один раз, около 10 минут)

Общий client_id rclone Google выводит из эксплуатации в 2026 году, поэтому нужен свой ([документация rclone](https://rclone.org/drive/#making-your-own-client-id)).

1. Откройте [Google Cloud Console](https://console.cloud.google.com/), создайте проект (например, `rclone-backup`).
2. **APIs & Services → Library** → найдите **Google Drive API** → **Enable**.
3. **Google Auth Platform** (экран согласия OAuth) → Get started: название, ваш e-mail, Audience — **External**.
4. **Data Access → Add scopes** → `.../auth/drive` → Save.
5. **Audience → Test users** → добавьте свой Gmail. Затем **PUBLISH APP**, иначе токен перестанет работать
   через 7 дней. Если кнопка неактивна, заполните в **Branding** домашнюю страницу, ссылку на политику
   конфиденциальности и домен (любой ваш сайт). Жёлтую плашку «requires verification» игнорируйте:
   для личного использования (до 100 пользователей) верификация не нужна.
6. **Clients → Create client** → тип **Desktop app** → сохраните **Client ID** и **Client secret**.

## 2. Подключите Google Drive к rclone

На компьютере с браузером:
```sh
rclone config create gdrive drive client_id=ВАШ_CLIENT_ID client_secret=ВАШ_SECRET scope=drive
```
Откроется браузер: войдите в Google, на экране «Google hasn't verified this app» нажмите
**Advanced → Go to … (unsafe)** (это ваше же приложение) и разрешите доступ. Проверка:
```sh
rclone about gdrive:
```
Для сервера без браузера: на сервере `rclone config create gdrive drive ... config_is_local=false`,
а токен получите на своём компьютере командой `rclone authorize "drive" ВАШ_CLIENT_ID ВАШ_SECRET`
([remote setup](https://rclone.org/remote_setup/)).

## 3. Копируйте

```powershell
.\backup.ps1 -Dest gdrive:Yandex-backup          # Windows
```
```sh
./scripts/backup.sh gdrive:Yandex-backup          # macOS, Linux
```

Для облака скрипты сами включают `--checksum`: каждый уже скопированный файл сверяется по MD5,
отличающиеся перезаливаются. Так что регулярный повторный запуск одновременно и докачивает, и проверяет.

## 4. Проверка

```sh
rclone check yandex: gdrive:Yandex-backup --one-way --missing-on-dst missing.txt --differ differ.txt
```
Яндекс и Google Drive оба хранят MD5, поэтому проверка ничего не скачивает и идёт быстро.

## 5. Если Яндекс откажет совсем

Копия в Google — обычные папки. Их видно в веб-версии, в приложении Google Диск на телефоне
и в [Google Drive для компьютера](https://support.google.com/drive/answer/13401938) (режим
«Потоковая передача»: структура видна целиком, файлы скачиваются при открытии, как у Яндекса).
Для автозагрузки фото с телефона в Google Drive: Android — Autosync for Google Drive,
iPhone — PhotoSync. Google Фото тоже подходит, но с 31.03.2025 его библиотеку нельзя
автоматически выгрузить сторонними программами ([rclone](https://rclone.org/googlephotos)).

[← назад к README](../README.md)
