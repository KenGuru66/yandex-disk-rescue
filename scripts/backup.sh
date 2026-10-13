#!/usr/bin/env bash
# Копирует Яндекс Диск в папку или облако. Только copy: в месте назначения ничего не удаляется.
# Повторный запуск докачивает то, что не скопировалось (в т. ч. файлы, которые Яндекс вернёт позже).
#
#   ./backup.sh /media/disk/YandexDisk
#   SOURCE="yandex:Документы" ./backup.sh gdrive:Yandex-backup
#   TRANSFERS=32 ./backup.sh /mnt/backup -- --dry-run      # после -- — любые флаги rclone
#
# Лог и список неудачных файлов кладутся в текущую папку.
set -uo pipefail
dest="${1:?Укажите, куда копировать: ./backup.sh /путь/к/папке  или  ./backup.sh gdrive:Yandex-backup}"
shift
[ "${1:-}" = "--" ] && shift
source_remote="${SOURCE:-yandex:}"
transfers="${TRANSFERS:-16}"

command -v rclone >/dev/null || { echo "rclone не найден: https://rclone.org/install/" >&2; exit 1; }

stamp="$(date +%F_%H%M%S)"
log="$PWD/yandex-rescue-$stamp.log"
failed="$PWD/yandex-rescue-$stamp-failed.txt"

extra=()
# Облако (gdrive:..., s3:...) — сравнение по MD5; локальная папка — по размеру и дате
[[ "$dest" =~ ^[A-Za-z][A-Za-z0-9_-]+: ]] && extra+=(--checksum)

echo "Копирую $source_remote -> $dest. Лог: $log"
# Яндекс сейчас долго выдаёт ссылки и часть файлов не отдаёт совсем: ждём минуту, повторяем один раз
rclone copy "$source_remote" "$dest" \
    --transfers "$transfers" --checkers 8 \
    --timeout 60s --contimeout 15s --low-level-retries 2 --retries 1 \
    --progress --stats 30s \
    --log-file "$log" --log-level INFO \
    ${extra[@]+"${extra[@]}"} "$@"
code=$?

sed -n 's/.* ERROR : \(.*\): Failed to copy.*/\1/p' "$log" 2>/dev/null | sort -u > "$failed"
copied=$(grep -c 'Copied (' "$log" 2>/dev/null)
nfail=$(wc -l < "$failed")

echo
echo "Скопировано файлов: $copied"
if [ "$nfail" -gt 0 ]; then
    echo "Не скопировано: $nfail (список: $failed)"
    echo "Обычно это файлы, которые Яндекс сейчас не отдаёт. Запустите этот же скрипт позже — он докачает только недостающее."
elif [ "$code" -eq 0 ]; then
    echo "Ошибок нет."
else
    echo "rclone завершился с ошибкой (код $code). Последние строки лога:"
    tail -n 5 "$log" | sed 's/^/  /'
fi
exit "$code"
