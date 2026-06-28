#requires -version 5.1
$ErrorActionPreference = 'Stop'

# ===== Config =====
$ScriptRoot    = 'C:\APOD'
$LogFile       = Join-Path $ScriptRoot 'apod.log'
$StateFile     = Join-Path $ScriptRoot 'last_run.txt'
$ImagesFolder  = 'C:\Users\diede\AppData\Local\APOD-Wallpaper\images'

# Add your NASA API key here:
$ApiKey        = 'YOUR_NASA_API_KEY_HERE'
$ApiUrl        = "https://api.nasa.gov/planetary/apod?api_key=$ApiKey"
$ApiUrlDemo    = "https://api.nasa.gov/planetary/apod?api_key=DEMO_KEY"  # fallback only

$MaxRetries    = 4
$RetryDelaySec = 8

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $LogFile -Value "[$ts] $Message"
}

function Test-AlreadyRanToday {
    if (Test-Path $StateFile) {
        $last = (Get-Content $StateFile -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
        if ($last -eq (Get-Date -Format 'yyyy-MM-dd')) { return $true }
    }
    return $false
}

function Mark-RanToday {
    Set-Content -Path $StateFile -Value (Get-Date -Format 'yyyy-MM-dd') -Encoding UTF8
}

function Set-WallpaperFit {
    param([string]$ImagePath)

    Add-Type @"
using System.Runtime.InteropServices;
public class Wallpaper {
  [DllImport("user32.dll", SetLastError = true)]
  public static extern bool SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@

    # Fit = full image visible without distortion
    Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name WallpaperStyle -Value '6'
    Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name TileWallpaper -Value '0'

    $ok = [Wallpaper]::SystemParametersInfo(20, 0, $ImagePath, 0x1 -bor 0x2)
    if (-not $ok) { throw "Failed to set wallpaper." }
}

function Invoke-WithRetry {
    param(
        [scriptblock]$ScriptBlock,
        [int]$Retries = 4,
        [int]$DelaySec = 8,
        [string]$ActionName = "operation"
    )

    for ($attempt = 1; $attempt -le $Retries; $attempt++) {
        try {
            return & $ScriptBlock
        }
        catch {
            $msg = $_.Exception.Message
            Write-Log "$ActionName failed (attempt $attempt/$Retries): $msg"

            if ($attempt -ge $Retries) { throw }
            Start-Sleep -Seconds $DelaySec
        }
    }
}

try {
    New-Item -ItemType Directory -Path $ScriptRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $ImagesFolder -Force | Out-Null
    if (-not (Test-Path $LogFile)) { New-Item -ItemType File -Path $LogFile -Force | Out-Null }

    if (Test-AlreadyRanToday) {
        Write-Log "Script already ran today. Exiting."
        exit 0
    }

    Write-Log "Starting APOD update via NASA API."

    # 1) Try personal API key first
    $apod = $null
    try {
        $apod = Invoke-WithRetry -Retries $MaxRetries -DelaySec $RetryDelaySec -ActionName "APOD API request (personal key)" -ScriptBlock {
            Invoke-RestMethod -Uri $ApiUrl -Method Get -TimeoutSec 30
        }
    }
    catch {
        Write-Log "Personal key request failed after retries. Trying DEMO_KEY fallback."
    }

    # 2) Fallback
    if (-not $apod) {
        $apod = Invoke-WithRetry -Retries 2 -DelaySec 5 -ActionName "APOD API request (DEMO_KEY)" -ScriptBlock {
            Invoke-RestMethod -Uri $ApiUrlDemo -Method Get -TimeoutSec 30
        }
    }

    if (-not $apod) {
        throw "Could not retrieve APOD metadata from API."
    }

    # Skip videos/non-images; keep previous wallpaper
    if ($apod.media_type -ne 'image') {
        Write-Log "APOD is not an image (media_type=$($apod.media_type)). Wallpaper unchanged."
        Mark-RanToday
        exit 0
    }

    $imgUrl = if ($apod.hdurl) { $apod.hdurl } else { $apod.url }
    if (-not $imgUrl) {
        Write-Log "No valid image URL received. Wallpaper unchanged."
        Mark-RanToday
        exit 0
    }

    $cleanUrl = ($imgUrl -split '\?')[0]
    $ext = [System.IO.Path]::GetExtension($cleanUrl).ToLowerInvariant()

    # Skip GIFs; keep previous wallpaper
    if ($ext -eq '.gif') {
        Write-Log "APOD is a GIF. Wallpaper unchanged."
        Mark-RanToday
        exit 0
    }

    if ([string]::IsNullOrWhiteSpace($ext)) { $ext = '.jpg' }

    $fileName = "apod_{0}{1}" -f (Get-Date -Format 'yyyyMMdd'), $ext
    $destPath = Join-Path $ImagesFolder $fileName

    Invoke-WithRetry -Retries $MaxRetries -DelaySec $RetryDelaySec -ActionName "Image download" -ScriptBlock {
        Invoke-WebRequest -Uri $imgUrl -OutFile $destPath -UseBasicParsing -TimeoutSec 60
    } | Out-Null

    Write-Log "Downloaded image to: $destPath"

    Set-WallpaperFit -ImagePath $destPath
    Write-Log "Wallpaper set successfully (Fit mode, no distortion)."

    Mark-RanToday
    Write-Log "Done."
}
catch {
    Write-Log ("ERROR: " + $_.Exception.Message)
    exit 1
}
