"""Собирает из логов rclone файлы, которые Яндекс не отдал («мёртвые»), и пишет фильтр для rclone.

    python3 make-filters.py [logs_dir] [папка ...]

logs/dead.txt        — список путей;
logs/filter-all.txt  — пропустить мёртвые, копировать всё остальное;
logs/filter-<n>.txt  — для каждой указанной папки: пропустить мёртвые, копировать только её
                       (так сначала спасают самое важное: python3 make-filters.py logs "Документы").

Фильтр нужен на время первичной заливки, чтобы потоки не ждали тайм-аутов на заведомо недоступных
файлах. Регулярный (ночной) запуск — без фильтра: он заново пробует всё и докачивает то, что Яндекс вернул.
"""
import glob
import os
import re
import sys

logs = sys.argv[1] if len(sys.argv) > 1 else "logs"
folders = sys.argv[2:]

dead = set()
for f in glob.glob(os.path.join(logs, "backup-*.log")):
    for line in open(f, encoding="utf-8", errors="replace"):
        m = re.match(r"^\S+ \S+ ERROR : (.+?): Failed to copy: failed to open source object", line)
        if m:
            dead.add(m.group(1))

esc = lambda p: re.sub(r"([\\\[\]\*\?\{\}])", r"\\\1", p)   # спецсимволы фильтров rclone
excl = ["- /" + esc(p) for p in sorted(dead)]

open(os.path.join(logs, "dead.txt"), "w", encoding="utf-8").write("\n".join(sorted(dead)) + "\n")
open(os.path.join(logs, "filter-all.txt"), "w", encoding="utf-8").write("\n".join(excl) + "\n")
for i, folder in enumerate(folders, 1):
    rules = excl + ["+ /" + esc(folder.strip("/")) + "/**", "- **"]
    open(os.path.join(logs, f"filter-{i}.txt"), "w", encoding="utf-8").write("\n".join(rules) + "\n")
    print(f"filter-{i}.txt: {folder}")
print(f"мёртвых файлов: {len(dead)} → {logs}/dead.txt, {logs}/filter-all.txt")
