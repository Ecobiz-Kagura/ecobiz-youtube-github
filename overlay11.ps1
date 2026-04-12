# =====================================================================
# overlay11.ps1
# 完全版：dark / light / epilogue を引数化・フォルダ先頭集約
# 確認なしで実行する版（実行形式は変更しない）
#
# 例:
#   .\overlay11.ps1 -OverlayTheme dark -OverlayFrom left
# =====================================================================

param(
  [string]$BackgroundVideoPath,
  [string]$OverlayVideoPath,

  [ValidateSet("dark","light","epilogue")]
  [string]$OverlayTheme = "dark",

  [ValidateSet("left","right","center")]
  [string]$OverlayFrom = "left",

  [string]$OverlayRootBase = "D:\images_for_slide_show",

  [int]$Margin = 10,

  [ValidateRange(0.0, 1.0)]
  [double]$OverlayAlpha = 0.6,

  [ValidateRange(0.01, 1.0)]
  [double]$OverlayRatio = 0.3,

  [string[]]$BackgroundExts = @("*.mp4","*.mov","*.mkv","*.webm")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

try {
  [Console]::InputEncoding  = [System.Text.UTF8Encoding]::new($false)
  [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
} catch {}

$OverlayFolderMap = @{
  "dark-left"       = "D:\images_for_slide_show\MP4s-dark\left"
  "dark-right"      = "D:\images_for_slide_show\MP4s-dark\right"
  "dark-center"     = "D:\images_for_slide_show\MP4s-dark\center"

  "light-left"      = "D:\images_for_slide_show\MP4s-light\left"
  "light-right"     = "D:\images_for_slide_show\MP4s-light\right"
  "light-center"    = "D:\images_for_slide_show\MP4s-light\center"

  "epilogue-left"   = "D:\images_for_slide_show\MP4s-epilogue\left"
  "epilogue-right"  = "D:\images_for_slide_show\MP4s-epilogue\right"
  "epilogue-center" = "D:\images_for_slide_show\MP4s-epilogue\center"
}

$sw = [System.Diagnostics.Stopwatch]::StartNew()

function Stamp([string]$msg) {
  Write-Host ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $msg)
}

function Assert-File([string]$p) {
  if ([string]::IsNullOrWhiteSpace($p)) {
    throw "Empty path"
  }
  if (-not (Test-Path -LiteralPath $p)) {
    throw ("Not found: {0}" -f $p)
  }
}

function Quote-Arg([string]$s) {
  if ($null -eq $s) { return '""' }
  if ($s -match '[\s"]') {
    return '"' + ($s -replace '"', '\"') + '"'
  }
  return $s
}

function Get-LatestVideoInCwd([string[]]$exts) {
  $cwd = (Get-Location).Path
  $files = foreach ($e in $exts) {
    Get-ChildItem -LiteralPath $cwd -File -Filter $e -ErrorAction SilentlyContinue
  }
  return ($files | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
}

function Pick-RandomOverlay([string]$base, [string]$theme, [string]$from) {
  $key = "$theme-$from"

  if ($OverlayFolderMap.ContainsKey($key)) {
    $dir = $OverlayFolderMap[$key]
  } else {
    $root = Join-Path $base ("MP4s-{0}" -f $theme)
    $dir  = Join-Path $root $from
  }

  if (-not (Test-Path -LiteralPath $dir)) {
    throw "オーバーレイ取得先が見つかりません: $dir"
  }

  $cands = Get-ChildItem -LiteralPath $dir -File -Filter *.mp4 -ErrorAction SilentlyContinue
  if (-not $cands) {
    throw "オーバーレイ動画がありません: $dir"
  }

  return ($cands | Get-Random).FullName
}

function Get-DurationSec([string]$path) {
  Assert-File $path

  $probeArgs = @(
    "-v", "error",
    "-show_entries", "format=duration",
    "-of", "default=nw=1:nk=1",
    $path
  )

  $out = & ffprobe @probeArgs 2>$null
  if ($LASTEXITCODE -ne 0 -or -not $out) {
    throw "ffprobe で duration を取得できません: $path"
  }

  $text = ($out | Out-String).Trim()
  $d = 0.0
  if (-not [double]::TryParse($text, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$d)) {
    throw "duration の解析に失敗しました: $path"
  }

  if ($d -le 0) {
    throw "duration が不正です: $d ($path)"
  }

  return $d
}

function Get-OverlayXY([string]$from, [int]$margin) {
  switch ($from) {
    "left"   { return @("$margin", "$margin") }
    "right"  { return @("main_w-overlay_w-$margin", "$margin") }
    "center" { return @("(main_w-overlay_w)/2", "$margin") }
    default  { return @("$margin", "$margin") }
  }
}

try {
  if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    throw "ffmpeg が見つかりません（PATH を確認）"
  }
  if (-not (Get-Command ffprobe -ErrorAction SilentlyContinue)) {
    throw "ffprobe が見つかりません（PATH を確認）"
  }

  if ([string]::IsNullOrWhiteSpace($BackgroundVideoPath)) {
    $latest = Get-LatestVideoInCwd -exts $BackgroundExts
    if (-not $latest) {
      throw "カレントディレクトリに動画がありません"
    }
    $BackgroundVideoPath = $latest.FullName
    Stamp "背景動画（自動）: $BackgroundVideoPath"
  } else {
    Stamp "背景動画（指定）: $BackgroundVideoPath"
  }

  Assert-File $BackgroundVideoPath
  $bg = (Resolve-Path -LiteralPath $BackgroundVideoPath).Path

  if ([string]::IsNullOrWhiteSpace($OverlayVideoPath)) {
    $OverlayVideoPath = Pick-RandomOverlay -base $OverlayRootBase -theme $OverlayTheme -from $OverlayFrom
    Stamp "オーバーレイ（自動）: theme=$OverlayTheme from=$OverlayFrom → $OverlayVideoPath"
  } else {
    Stamp "オーバーレイ（指定）: $OverlayVideoPath"
  }

  Assert-File $OverlayVideoPath
  $ov = (Resolve-Path -LiteralPath $OverlayVideoPath).Path

  $dir  = Split-Path $bg -Parent
  $base = [IO.Path]::GetFileNameWithoutExtension($bg)
  $ext  = [IO.Path]::GetExtension($bg)
  $ts   = Get-Date -Format "yyyyMMddHHmmss"
  $backup = Join-Path $dir ("{0}_backup_{1}{2}" -f $base, $ts, $ext)

  Copy-Item -LiteralPath $bg -Destination $backup -Force
  Stamp "バックアップ作成: $backup"

  $dur = Get-DurationSec $backup
  Stamp ("背景の長さ: {0:F3} 秒" -f $dur)

  $xy = Get-OverlayXY -from $OverlayFrom -margin $Margin
  $x = $xy[0]
  $y = $xy[1]

  # scale2ref を使って背景幅基準で overlay を縮小
  # rw = reference width (= 背景幅)
  # h = ow/a で縦横比維持
  $filter =
    ("[1:v][0:v]scale2ref=w=rw*{0}:h=ow/a[ovl][base];" -f $OverlayRatio) +
    ("[ovl]format=yuva420p,colorchannelmixer=aa={0}[ovla];" -f $OverlayAlpha) +
    ("[base][ovla]overlay=x={0}:y={1}:format=auto[vout]" -f $x, $y)

  Write-Host ""
  Write-Host "[FILTER] $filter"
  Write-Host ""

  $ffArgs = @(
    "-y",
    "-i", $backup,
    "-stream_loop", "-1",
    "-i", $ov,
    "-filter_complex", $filter,
    "-map", "[vout]",
    "-map", "0:a?",
    "-t", ("{0:F3}" -f $dur),
    "-c:v", "libx264",
    "-preset", "ultrafast",
    "-crf", "28",
    "-pix_fmt", "yuv420p",
    "-c:a", "copy",
    "-movflags", "+faststart",
    $bg
  )

  $cmdPreview = "ffmpeg " + (($ffArgs | ForEach-Object { Quote-Arg $_ }) -join " ")
  Write-Host "[CMD] $cmdPreview"
  Write-Host ""

  Stamp "ffmpeg 開始（出力は元と同名）"

  & ffmpeg @ffArgs
  $exitCode = $LASTEXITCODE

  if ($exitCode -ne 0) {
    throw "ffmpeg 失敗 (ExitCode=$exitCode)"
  }

  Write-Host ""
  Write-Host "完了"
  Write-Host "  - 出力: $bg（元と同名）"
  Write-Host "  - バックアップ: $backup"
  Write-Host ("  - サイズ: 背景横幅の{0:P0}" -f $OverlayRatio)
  Write-Host "  - Theme/From: $OverlayTheme / $OverlayFrom"
  Write-Host ("  - 位置: x={0}, y={1}, margin={2}" -f $x, $y, $Margin)
}
catch {
  Write-Error $_
  exit 1
}
finally {
  $sw.Stop()
  $e = $sw.Elapsed
  Write-Host ("処理時間: {0:00}:{1:00}:{2:00}.{3:000}" -f [int]$e.TotalHours, $e.Minutes, $e.Seconds, $e.Milliseconds)
}