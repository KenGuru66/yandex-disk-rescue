#!/usr/bin/env bash
# Подключает Яндекс Диск к rclone по токену Полигона (Linux, macOS).
#
#   ./add-yandex-remote.sh [имя]        # имя подключения, по умолчанию yandex
#
# Токен берётся на https://yandex.ru/dev/disk/poligon/ (кнопка «Получить OAuth-токен»).
# Почему не `rclone config`: приложению rclone Яндекс сейчас отвечает 410 GoneError на любые файлы.
set -euo pipefail
name="${1:-yandex}"

command -v rclone >/dev/null || { echo "rclone не найден: https://rclone.org/install/ (macOS: brew install rclone)" >&2; exit 1; }

conf="$(rclone config file | tail -n 1)"
if [ -f "$conf" ] && grep -q "^\[$name\]" "$conf"; then
    echo "Подключение [$name] уже есть в $conf. Укажите другое имя: $0 yandex2" >&2
    exit 1
fi

read -r -s -p "Вставьте токен Полигона (ввод не отображается): " token; echo
token="$(printf '%s' "$token" | tr -d '[:space:]')"
[[ "$token" =~ ^[A-Za-z0-9_.-]{20,}$ ]] || { echo "Это не похоже на токен Полигона." >&2; exit 1; }

# refresh_token — заглушка: без него rclone не стартует; expiry в будущем, чтобы rclone не пытался обновлять токен.
mkdir -p "$(dirname "$conf")"
umask 077
printf '\n[%s]\ntype = yandex\ntoken = {"access_token":"%s","token_type":"OAuth","refresh_token":"unused","expiry":"2099-01-01T00:00:00Z"}\n' \
    "$name" "$token" >> "$conf"
chmod 600 "$conf"

echo "Проверяю доступ..."
if rclone about "$name:"; then
    echo "Готово: подключение [$name] записано в $conf"
else
    echo "Не получилось: токен истёк или скопирован не полностью. Удалите секцию [$name] из $conf и повторите." >&2
    exit 1
fi
