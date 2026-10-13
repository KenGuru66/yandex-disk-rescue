# macOS и Linux: Яндекс Диск → внешний диск

[← назад к README](../README.md)

## 1. Установите rclone (1.75 или новее)

```sh
brew install rclone                       # macOS (Homebrew)
sudo -v ; curl https://rclone.org/install.sh | sudo bash   # Linux (официальный установщик)
rclone version
```
Пакеты из репозиториев дистрибутивов часто старые, лучше официальный установщик.

## 2. Подключите Яндекс Диск

Возьмите токен на [Полигоне Яндекс Диска](https://yandex.ru/dev/disk/poligon/) («Получить OAuth-токен»,
войдя в нужный аккаунт), затем:

```sh
git clone https://github.com/KenGuru66/yandex-disk-rescue.git
cd yandex-disk-rescue
./scripts/add-yandex-remote.sh
```

Скрипт спросит токен (ввод скрыт), допишет секцию `[yandex]` в конфиг rclone (права 600) и покажет
объём Диска. Почему Полигон, а не `rclone config`: [how-it-works.md](how-it-works.md#почему-токен-полигона).

## 3. Копируйте

```sh
./scripts/backup.sh /Volumes/Backup/YandexDisk        # macOS
./scripts/backup.sh /media/$USER/Backup/YandexDisk    # Linux
```

- Только часть Диска: `SOURCE="yandex:Документы" ./scripts/backup.sh ...`
- Больше потоков: `TRANSFERS=32 ./scripts/backup.sh ...`
- Любые флаги rclone — после `--`: `./scripts/backup.sh /mnt/backup -- --dry-run`

Лог и список несохранённых файлов (`yandex-rescue-<дата>-failed.txt`) — в текущей папке. На macOS не давайте
ноутбуку уснуть: `caffeinate -i ./scripts/backup.sh ...`.

## 4. Повторяйте и проверяйте

Каждую ночь (`crontab -e`):
```
17 3 * * * cd $HOME/yandex-disk-rescue && ./scripts/backup.sh /media/backup/YandexDisk >/dev/null 2>&1
```

Проверка по MD5:
```sh
rclone check yandex: /media/backup/YandexDisk --one-way --missing-on-dst missing.txt --differ differ.txt
```

## 5. Когда закончите — отзовите токен

[troubleshooting → как отозвать токен](troubleshooting.md#как-отозвать-токен)

[← назад к README](../README.md)
