#!/bin/bash
# Яндекс Диск -> облако на сервере, rclone в Docker. Только copy: в месте назначения ничего не удаляется.
#
#   DEST=gdrive:Yandex-backup ./run-backup.sh                    # весь Диск
#   DEST=gdrive:Yandex-backup ./run-backup.sh --filter-from /logs/filter-all.txt   # пропустить «мёртвые» файлы
#
# Переменные: DEST (обязательно), SOURCE (yandex:), TRANSFERS (32), BWLIMIT (off, напр. 20M),
#             CPUS (0.85), MEMORY (550m) — лимиты контейнера, если на сервере крутится что-то ещё.
# Каталог рядом со скриптом: config/rclone.conf (права 600), logs/ — логи и фильтры.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
DEST="${DEST:?укажите DEST, например DEST=gdrive:Yandex-backup}"
SOURCE="${SOURCE:-yandex:}"
TRANSFERS="${TRANSFERS:-32}"
BWLIMIT="${BWLIMIT:-off}"
IMAGE="rclone/rclone:1.75.2"

mkdir -p "$DIR/logs"
exec 9>"$DIR/.lock"
flock -n 9 || { echo "уже запущен, выхожу"; exit 0; }
find "$DIR/logs" -name "backup-*.log" -mtime +30 -delete 2>/dev/null || true

extra=()
[[ "$DEST" =~ ^[A-Za-z][A-Za-z0-9_-]+: ]] && extra+=(--checksum)   # облако: сравнение по MD5

LOG="/logs/backup-$(date +%F_%H%M).log"
docker run --rm --name yandex-backup --cpus "${CPUS:-0.85}" --memory "${MEMORY:-550m}" \
  --user "$(id -u):$(id -g)" -e RCLONE_CONFIG=/config/rclone.conf -e XDG_CACHE_HOME=/tmp \
  -v "$DIR/config:/config" -v "$DIR/logs:/logs" \
  "$IMAGE" copy "$SOURCE" "$DEST" \
  --transfers "$TRANSFERS" --checkers 8 --tpslimit 20 \
  --buffer-size 1M --drive-chunk-size 4M \
  --drive-stop-on-upload-limit --bwlimit "$BWLIMIT" \
  --retries 1 --low-level-retries 2 --timeout 60s --contimeout 15s \
  --log-file "$LOG" --log-level INFO --stats 5m --stats-log-level NOTICE \
  ${extra[@]+"${extra[@]}"} "$@"
