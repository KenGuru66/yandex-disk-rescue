# VPS + Docker: копирование в облако по расписанию

Для тех, у кого есть сервер (VPS) с Docker и кто хочет, чтобы копия в облаке обновлялась каждую ночь
без включённого домашнего компьютера. На сервере место не нужно: rclone гонит файлы из Яндекса
в облако потоком.

[← назад к README](../README.md)

## Что проверено

Сервер с 1 vCPU и 1 ГБ RAM (рядом работал VPN), Docker, образ `rclone/rclone:1.75.2`, Google Drive 2 ТБ.
С 64 потоками rclone занимал около 310 МБ памяти и до 40% одного ядра, скорость доходила до 33 МБ/с.
Трафик: всё, что копируется, проходит через сервер дважды (вход и выход), проверьте лимиты тарифа.

## 1. Каталог и конфиг

```sh
mkdir -p ~/yandex-backup/config ~/yandex-backup/logs && chmod 700 ~/yandex-backup
cd ~/yandex-backup
curl -fsSLO https://raw.githubusercontent.com/KenGuru66/yandex-disk-rescue/main/vps/run-backup.sh
curl -fsSLO https://raw.githubusercontent.com/KenGuru66/yandex-disk-rescue/main/vps/make-filters.py
chmod 700 run-backup.sh
```

`config/rclone.conf` (права 600) должен содержать два подключения: `[yandex]` и облако, например `[gdrive]`.
Проще всего создать их на своём компьютере ([windows.md](windows.md), [google-drive.md](google-drive.md))
и скопировать нужные секции. Структура — в [`vps/rclone.conf.example`](../vps/rclone.conf.example).

Проверка из контейнера:
```sh
docker run --rm --user $(id -u):$(id -g) -e RCLONE_CONFIG=/config/rclone.conf \
  -v ~/yandex-backup/config:/config rclone/rclone:1.75.2 about yandex:
```

## 2. Первый запуск

```sh
cd ~/yandex-backup
DEST=gdrive:Yandex-backup setsid nohup ./run-backup.sh > logs/run.out 2>&1 < /dev/null &
tail -f "$(ls -t logs/backup-*.log | head -1)"
```

Переменные: `DEST` (обязательно), `SOURCE` (`yandex:`), `TRANSFERS` (32), `BWLIMIT` (`off` или, например, `20M`),
`CPUS` и `MEMORY` (лимиты контейнера: 0.85 и 550m).

- Ограничение скорости в идущем запуске включается и выключается сигналом: `docker kill --signal=SIGUSR2 yandex-backup`.
- Для облака скрипт добавляет `--checksum`: уже скопированные файлы сверяются по MD5.
- Лимит Google 750 ГБ в сутки: rclone остановится сам (`--drive-stop-on-upload-limit`), ночной запуск продолжит.

## 3. Сначала самое важное, мёртвые файлы — потом

Когда Яндекс не отдаёт часть файлов, потоки тратят время на тайм-ауты. Чтобы быстрее спасти доступное,
после первого прохода соберите список «мёртвых» файлов и запускайте с фильтром:

```sh
python3 make-filters.py logs "Документы" "Фото/2024"      # filter-all.txt + filter-1.txt, filter-2.txt
DEST=gdrive:Yandex-backup ./run-backup.sh --filter-from /logs/filter-1.txt   # только «Документы», без мёртвых
DEST=gdrive:Yandex-backup ./run-backup.sh --filter-from /logs/filter-all.txt # всё остальное, без мёртвых
```

> [!NOTE]
> Пути в логе rclone считаются от корня `SOURCE` того запуска. Используйте фильтр с тем же `SOURCE`,
> с которым были сделаны запуски, по логам которых он собран (по умолчанию `yandex:`, весь Диск).

Регулярный ночной запуск — **без** фильтра: он заново пробует все файлы и докачивает те, что Яндекс вернул.

## 4. Расписание

```sh
crontab -e
```
```
23 2 * * * DEST=gdrive:Yandex-backup /home/USER/yandex-backup/run-backup.sh >> /home/USER/yandex-backup/logs/cron.out 2>&1
```
`flock` внутри скрипта не даст стартовать второму запуску, пока идёт первый. Логи старше 30 дней удаляются.

## 5. Проверка

```sh
docker run --rm --user $(id -u):$(id -g) -e RCLONE_CONFIG=/config/rclone.conf -v ~/yandex-backup/config:/config \
  rclone/rclone:1.75.2 check yandex: gdrive:Yandex-backup --one-way --missing-on-dst - 2>/dev/null | wc -l
```
Число — сколько файлов Диска ещё нет в копии.

## Бэкап самого конфига

В `config/rclone.conf` лежат токены от Яндекса и облака. Храните его копию в надёжном месте
(например, в зашифрованном виде) и никогда не публикуйте.

[← назад к README](../README.md)
