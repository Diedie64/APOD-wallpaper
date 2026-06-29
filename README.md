# APOD Wallpaper (Windows)

This repository contains a PowerShell script that sets your Windows desktop wallpaper to NASA's **Astronomy Picture of the Day (APOD)**.

The script is designed to:
- run once per day (first login/start of the day),
- download the APOD image,
- set it as wallpaper with **Fit** mode (full image visible, no distortion),
- skip APOD entries that are videos or GIFs (keep previous wallpaper),
- log all actions to a log file.

---

## 1) Requirements

- Windows 10/11
- PowerShell 5.1 or newer
- Internet connection

---

## 2) Repository Files

- `Set-APODWallpaper.ps1` → main script

The script uses this local folder:
- Script + log + run-state + downloaded images:
  - `C:\APOD`

---

## 3) Get a NASA API Key

1. Open: https://api.nasa.gov/
2. Click **Generate API Key** (or equivalent sign-up option).
3. Fill in the required info and submit.
4. Copy your API key.

---

## 4) Add API Key to the Script

Open `Set-APODWallpaper.ps1` and replace:

```powershell
$ApiKey = 'YOUR_NASA_API_KEY_HERE'
```

with your real key, for example:

```powershell
$ApiKey = 'abc123...'
```

Save the file.

---

## 5) First Manual Test Run

Open PowerShell and run:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\APOD\Set-APODWallpaper.ps1"
```

Check the log:

```powershell
Get-Content "C:\APOD\apod.log" -Tail 80
```

Check downloaded files:

```powershell
Get-ChildItem "C:\APOD" | Sort-Object LastWriteTime -Descending | Select-Object -First 10 Name,LastWriteTime,Length
```

If needed, force a re-run on the same day:

```powershell
Remove-Item "C:\APOD\last_run.txt" -ErrorAction SilentlyContinue
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\APOD\Set-APODWallpaper.ps1"
```

---

## 6) Run Automatically at Login

Create a scheduled task:

```powershell
$taskName = "APOD Daily Wallpaper"
$script   = "C:\APOD\APOD.ps1"

$action   = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$script`""
$trigger  = New-ScheduledTaskTrigger -AtLogOn
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Description "Set NASA APOD as wallpaper at logon"
```

This task runs at every logon.
---

## 7) Behavior Notes

- If APOD is a **video** (`media_type != image`), wallpaper is not changed.
- If APOD image is a **GIF**, wallpaper is not changed.
- On API/network errors (e.g. HTTP 503), the script retries automatically.
- If your personal API call fails, it tries `DEMO_KEY` as a fallback.

