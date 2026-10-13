# yandex-disk-rescue: back up all of Yandex Disk with rclone (English guide)

How to copy an entire Yandex Disk, including photos in the "unlimited" photo storage, to a local drive
or to Google Drive with rclone, while Yandex restricts downloads and does not serve part of the files.

Everything here was tested on 13 October 2026 on one live account: 1.8 TB of files, 152 GiB
(about 30,000 photos) in the unlimited storage, rclone 1.75.2, Windows PowerShell 5.1, bash in WSL
(Ubuntu 24.04) and Docker on a VPS. Your account may behave differently.

The scripts print their messages in Russian; the commands and parameters below are all you need.

[← README](../../README.md) · [Russian docs](../windows.md)

## Contents

- [Why the usual rclone setup fails](#why-the-usual-rclone-setup-fails)
- [1. Install rclone](#1-install-rclone)
- [2. Connect Yandex Disk with a Polygon token](#2-connect-yandex-disk-with-a-polygon-token)
- [3. Copy to a local drive](#3-copy-to-a-local-drive)
- [4. Copy to Google Drive](#4-copy-to-google-drive)
- [5. Repeat every day](#5-repeat-every-day)
- [6. Verify the copy by MD5](#6-verify-the-copy-by-md5)
- [7. Photos in the unlimited storage](#7-photos-in-the-unlimited-storage)
- [8. Run on a VPS with Docker](#8-run-on-a-vps-with-docker)
- [9. Errors](#9-errors)
- [10. Revoke the token when you are done](#10-revoke-the-token-when-you-are-done)

## Why the usual rclone setup fails

In October 2026, after drone attacks damaged three Yandex data centers (Sasovo, Kaluga, Vladimir),
Yandex disabled bulk downloads in the Disk web interface. On the tested account:

- rclone's own OAuth app gets `410 GoneError` on every file operation, while `/v1/disk` still answers `200`.
  A token from Yandex Polygon (Yandex's own REST API playground) works.
- Photos uploaded with unlimited autoupload live in a separate area, `photounlim`. Neither the REST API
  (`DiskAreaDoesNotExistsError`) nor WebDAV (`404`) lists them, so rclone cannot see them.
- 154 of 300 randomly sampled files could not be downloaded at all; a second pass gave the same result.
  Their download links redirect to `*.klg.storage.yandex.net` (Kaluga) storage nodes that accept the
  connection and never answer.
- Getting a download link took 1 to 60 seconds, sometimes ending with `500`.
- WebDAV answered `503` under load and gave about 0.2 MB/s per stream; REST gave about 0.8 MB/s and returns MD5.

So this guide uses the REST backend with a Polygon token, short timeouts so dead files fail fast,
`copy` instead of `sync`, and MD5 verification.

> [!IMPORTANT]
> Never use `rclone sync` for this backup. It deletes files in the destination that are missing on Yandex Disk.

## 1. Install rclone

You need rclone 1.75 or newer.

Windows (PowerShell; reopen PowerShell after installing):

```powershell
winget install Rclone.Rclone
rclone version
```

macOS and Linux (distribution packages are often outdated, prefer the official installer on Linux):

```sh
brew install rclone                                          # macOS
sudo -v ; curl https://rclone.org/install.sh | sudo bash     # Linux
rclone version
```

## 2. Connect Yandex Disk with a Polygon token

Open the [Yandex Disk Polygon](https://yandex.ru/dev/disk/poligon/), sign in to the account you want to
back up and click "Получить OAuth-токен" (Get OAuth token). Copy the token. It grants full access to
your Disk and is valid for about a year: keep it secret and revoke it when you are done.

The connection script asks for the token (input is hidden), adds a `[yandex]` remote to the rclone
config and prints Total/Used/Free of your Disk.

Windows:

```powershell
irm https://raw.githubusercontent.com/KenGuru66/yandex-disk-rescue/main/scripts/add-yandex-remote.ps1 -OutFile add-yandex-remote.ps1
powershell -ExecutionPolicy Bypass -File .\add-yandex-remote.ps1
```

macOS and Linux (an optional argument sets the remote name, default `yandex`):

```sh
git clone https://github.com/KenGuru66/yandex-disk-rescue.git
cd yandex-disk-rescue
./scripts/add-yandex-remote.sh
```

### Manual setup without the script

The rclone `yandex` backend refuses to start without a `refresh_token` (`unable to get RefreshToken`),
and a Polygon token has none. Add a placeholder refresh token and a far expiry date, so rclone never
tries to refresh it. Append this section to the file shown by `rclone config file`:

```ini
[yandex]
type = yandex
token = {"access_token":"YOUR_POLYGON_TOKEN","token_type":"OAuth","refresh_token":"unused","expiry":"2099-01-01T00:00:00Z"}
```

Check the connection:

```sh
rclone about yandex:
```

## 3. Copy to a local drive

The backup script runs `rclone copy` with fail-fast timeouts, writes a log and a list of files that
were not copied (`yandex-rescue-<date>-failed.txt`) to the current folder. Re-running it copies only
what is still missing.

Windows (`-Source` copies a single folder, `-Transfers` sets parallel streams, default 16):

```powershell
irm https://raw.githubusercontent.com/KenGuru66/yandex-disk-rescue/main/scripts/backup.ps1 -OutFile backup.ps1
powershell -ExecutionPolicy Bypass -File .\backup.ps1 -Dest E:\YandexDisk
powershell -ExecutionPolicy Bypass -File .\backup.ps1 -Dest E:\YandexDisk -Source "yandex:Documents" -Transfers 32
```

macOS and Linux (`SOURCE` and `TRANSFERS` environment variables, extra rclone flags after `--`):

```sh
./scripts/backup.sh /Volumes/Backup/YandexDisk                     # macOS
./scripts/backup.sh /media/$USER/Backup/YandexDisk                 # Linux
SOURCE="yandex:Documents" TRANSFERS=32 ./scripts/backup.sh /mnt/backup -- --dry-run
```

### The same copy without scripts

rclone waits 5 minutes and retries 10 times by default, so streams get stuck on files Yandex does not
serve. With these flags a dead file fails in 1-2 minutes and a slow but live file still completes:

```sh
rclone copy yandex: /mnt/backup/YandexDisk \
  --transfers 16 --checkers 8 \
  --timeout 60s --contimeout 15s --low-level-retries 2 --retries 1 \
  --progress --log-file rescue.log --log-level INFO
```

List the files that were not copied:

```sh
grep " ERROR : " rescue.log
```

Exit code `5` means some files were not copied: expected while Yandex does not serve them. Run the copy again later.

## 4. Copy to Google Drive

Files stream from Yandex to Google through your computer or server; no local disk space is needed.
Google accepts at most 750 GB of uploads per day, so `--drive-stop-on-upload-limit` stops the run
and the next run continues.

rclone's shared Google client_id is being retired in 2026, so create your own
([rclone docs](https://rclone.org/drive/#making-your-own-client-id)): a Google Cloud project with the
Google Drive API enabled, an External OAuth consent screen with the `.../auth/drive` scope, and a
Desktop app client. Publish the app ("In production"), otherwise the token stops working after 7 days.

```sh
rclone config create gdrive drive client_id=YOUR_CLIENT_ID client_secret=YOUR_SECRET scope=drive
rclone about gdrive:
```

On a server without a browser, create the remote with `config_is_local=false` and get the token on your
computer with `rclone authorize "drive" YOUR_CLIENT_ID YOUR_SECRET` ([remote setup](https://rclone.org/remote_setup/)).

Copy with the scripts; for a cloud destination they add `--checksum`, so every re-run also re-checks MD5:

```powershell
.\backup.ps1 -Dest gdrive:Yandex-backup
```

```sh
./scripts/backup.sh gdrive:Yandex-backup
```

Or directly with rclone:

```sh
rclone copy yandex: gdrive:Yandex-backup --checksum \
  --transfers 32 --checkers 8 \
  --timeout 60s --contimeout 15s --low-level-retries 2 --retries 1 \
  --drive-stop-on-upload-limit --progress
```

## 5. Repeat every day

Each run skips files that are already copied and retries the rest, including files Yandex
did not serve yesterday.

Windows Task Scheduler, every day at 03:00:

```powershell
$a = "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PWD\backup.ps1`" -Dest E:\YandexDisk"
Register-ScheduledTask -TaskName "yandex-disk-rescue" -Trigger (New-ScheduledTaskTrigger -Daily -At 3am) `
  -Action (New-ScheduledTaskAction -Execute powershell.exe -Argument $a -WorkingDirectory $PWD)
```

Remove the task with `Unregister-ScheduledTask yandex-disk-rescue -Confirm:$false`.

macOS and Linux cron (`crontab -e`):

```text
17 3 * * * cd $HOME/yandex-disk-rescue && ./scripts/backup.sh /media/backup/YandexDisk >/dev/null 2>&1
```

## 6. Verify the copy by MD5

`rclone check` compares every file by MD5. `missing.txt` lists files not yet in the copy,
`differ.txt` lists files that differ and should be empty:

```sh
rclone check yandex: /media/backup/YandexDisk --one-way --missing-on-dst missing.txt --differ differ.txt
```

Yandex Disk and Google Drive both store MD5, so checking a Google Drive copy downloads nothing:

```sh
rclone check yandex: gdrive:Yandex-backup --one-way --missing-on-dst missing.txt --differ differ.txt
```

## 7. Photos in the unlimited storage

Photos from unlimited autoupload are visible only in the "Фото" (Photos) section of the web interface.
To back them up, move them to a regular folder first. After the move they count towards your storage
quota, so check that you have enough free space. The API shows the size of the unlimited area:

```sh
curl -s -H "Authorization: OAuth YOUR_POLYGON_TOKEN" "https://cloud-api.yandex.net/v1/disk/?fields=photounlim_size,total_space,used_space"
```

Free space is `total_space - used_space`; it must be at least `photounlim_size`.

Three ways to get them out:

1. The Yandex Disk desktop app can copy all photos, including unlimited ones, to your computer
   (Settings, Autoupload, "Копировать фото и видео на компьютер"). Since 3 June 2026 the desktop app
   syncs files only with a Yandex 360 subscription. Not tested during the restrictions.
2. Manually in the web interface: Photos, the "Безлимит" (Unlimited) filter, select up to 500 photos
   with Shift, Move to a regular folder. Repeat until the section is empty.
3. Automatically with `tools/yd.js`, described below.

### Move unlimited photos with yd.js

`yd.js` does what the web interface does: it lists the `photounlim` area and moves files in batches of
up to 40 (Yandex rejects larger batches with `Too many items`). Requests run inside your own browser tab
over the Chrome DevTools Protocol, with your session cookies. On the test account it moved 30,738 files
(152 GiB) in about 6 hours; 49 failed with `500` on the Yandex side.

> [!WARNING]
> This is the undocumented internal API of the Yandex Disk web client and can change at any time.
> The script only moves files, it never deletes them.

You need Node.js 18+ and Chrome or another Chromium browser:

```sh
git clone https://github.com/KenGuru66/yandex-disk-rescue.git
cd yandex-disk-rescue/tools
npm install
```

Create the destination folder on your Disk. The default is `Безлимит`; to use another folder,
set `YD_DEST`:

```sh
export YD_DEST=Unlimited          # PowerShell: $env:YD_DEST = "Unlimited"
```

Start a separate browser instance with a debugging port and a separate profile, sign in to Yandex in
that window and keep the Disk tab open:

```powershell
# Windows
& "C:\Program Files\Google\Chrome\Application\chrome.exe" --remote-debugging-port=9222 --user-data-dir="$env:TEMP\yd-profile" https://disk.yandex.ru/client/photo
```

```sh
# macOS
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --remote-debugging-port=9222 --user-data-dir=/tmp/yd-profile https://disk.yandex.ru/client/photo
# Linux (in WSL add --ozone-platform=wayland --disable-gpu)
google-chrome --remote-debugging-port=9222 --user-data-dir=/tmp/yd-profile https://disk.yandex.ru/client/photo
```

List the unlimited area (read-only, 5-15 minutes for 30,000 photos), then move up to 100,000 files
in batches of 40:

```sh
node yd.js list state
node yd.js move state 100000 40
```

`state` is the folder for the file list and the move journal. Running `move` again resumes and retries
only failed files. If Yandex shows a captcha, the script stops: solve it in the browser window and run
`move` again. When finished, close the browser and delete the `yd-profile` folder: it holds your session cookies.

Tested on Linux (WSL) with Chrome; Windows and macOS commands are the same but were not run.

## 8. Run on a VPS with Docker

A VPS copies Yandex Disk to the cloud every night without your computer. No disk space is needed on the
server, but all traffic passes through it twice. Tested on 1 vCPU and 1 GB RAM with the
`rclone/rclone:1.75.2` image: 64 streams used about 310 MB of RAM and up to 40% of one core,
with speeds up to 33 MB/s.

```sh
mkdir -p ~/yandex-backup/config ~/yandex-backup/logs && chmod 700 ~/yandex-backup
cd ~/yandex-backup
curl -fsSLO https://raw.githubusercontent.com/KenGuru66/yandex-disk-rescue/main/vps/run-backup.sh
curl -fsSLO https://raw.githubusercontent.com/KenGuru66/yandex-disk-rescue/main/vps/make-filters.py
chmod 700 run-backup.sh
```

Put the `[yandex]` and `[gdrive]` sections into `config/rclone.conf` (mode 600; see
[`vps/rclone.conf.example`](../../vps/rclone.conf.example)) and check them from the container:

```sh
docker run --rm --user $(id -u):$(id -g) -e RCLONE_CONFIG=/config/rclone.conf \
  -v ~/yandex-backup/config:/config rclone/rclone:1.75.2 about yandex:
```

Start the first run in the background. Variables: `DEST` (required), `SOURCE` (default `yandex:`),
`TRANSFERS` (32), `BWLIMIT` (`off` or e.g. `20M`), `CPUS` and `MEMORY` (container limits, 0.85 and 550m):

```sh
DEST=gdrive:Yandex-backup setsid nohup ./run-backup.sh > logs/run.out 2>&1 < /dev/null &
tail -f "$(ls -t logs/backup-*.log | head -1)"
```

Nightly run with cron; `flock` inside the script prevents overlapping runs, logs older than 30 days are deleted:

```text
23 2 * * * DEST=gdrive:Yandex-backup /home/USER/yandex-backup/run-backup.sh >> /home/USER/yandex-backup/logs/cron.out 2>&1
```

### Save important folders first, skip dead files

During the first upload, dead files waste time on timeouts. After the first pass, build a filter from the
logs and copy the important folders first. Filter paths are relative to the `SOURCE` of the logged runs:

```sh
python3 make-filters.py logs "Documents" "Photos/2024"                        # filter-all.txt, filter-1.txt, filter-2.txt
DEST=gdrive:Yandex-backup ./run-backup.sh --filter-from /logs/filter-1.txt    # only Documents, without dead files
DEST=gdrive:Yandex-backup ./run-backup.sh --filter-from /logs/filter-all.txt  # everything else, without dead files
```

Keep the regular nightly run without a filter: it retries every file and picks up those Yandex brings back.

## 9. Errors

| In the log | Meaning | Fix |
|---|---|---|
| `410 GoneError` on any folder | the remote was created by `rclone config` with rclone's own app | reconnect with a Polygon token (step 2) |
| `unable to get RefreshToken` | no `refresh_token` in the `[yandex]` section | add `"refresh_token":"unused"` (step 2) |
| `401 Unauthorized` | the Polygon token expired or was revoked | get a new token and replace `access_token` |
| `timeout awaiting response headers`, `500 Internal Server Error` | the file sits on a Yandex storage node that does not answer now | nothing; run the copy again later |
| `failed to open source object: 503` | WebDAV is overloaded | use the REST `yandex` remote, not WebDAV |
| Google `403 User rate limit exceeded` | more than 750 GB uploaded today | continue tomorrow |
| `Too many items` in `yd.js` | batch larger than 40 | `node yd.js move state 100000 40` |
| exit code `5` | some files were not copied | expected now; see `*-failed.txt` and run again later |

## 10. Revoke the token when you are done

The Polygon token gives full access to your Disk for about a year.

```sh
rclone config delete yandex
```

Then, in [Yandex ID](https://id.yandex.ru), open the list of apps with access to your account and
disconnect the Yandex Disk Polygon app. If you cannot find it, change your password and sign out on all devices.
