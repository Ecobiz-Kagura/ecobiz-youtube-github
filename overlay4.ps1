# =====================================================================
# overlay-auto.ps1（完全版：出力ファイル名＝元と同じ）
# =====================================================================

param(
  [string]$BackgroundVideoPath,
  [string]$OverlayVideoPath,

  [ValidateSet("left","right","center")]
  [string]$OverlayFrom = "left",

  [string]$OverlayRoot = "D:\images_for_slide_show\MP4s-dark",

  [int]$Margin = 10,
  [ValidateRange(0.0,1.0)][double]$OverlayAlpha = 0.6,
  [ValidateRange(0.01,1.0)][double]$OverlayRatio = 0.3,

  [string[]]$BackgroundExts = @("*.mp4","*.mov","*.mkv","*.webm")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ========= タイマー =========
$sw = [System.Diagnostics.Stopwatch]::StartNew()
function Stamp($m){ Write-Host ("[{0}] {1}" -f (Get-Date -Format HH:mm:ss), $m) }

function Get-LatestVideoInCwd($exts){
  foreach($e in $exts){
    Get-ChildItem -LiteralPath (Get-Location) -File -Filter $e -ErrorAction SilentlyContinue
  } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

function Pick-RandomOverlay($root,$from){
  $dir = Join-Path $root $from
  if (-not (Test-Path $dir)) { throw "Overlay dir not found: $dir" }
  $c = Get-ChildItem $dir -File -Filter *.mp4
  if (-not $c) { throw "Overlay mp4 not found in: $dir" }
  ($c | Get-Random).FullName
}

try {
  if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    throw "ffmpeg not found"
  }

  # ===== 背景動画 =====
  if ([string]::IsNullOrWhiteSpace($BackgroundVideoPath)) {
    $latest = Get-LatestVideoInCwd $BackgroundExts
    if (-not $latest) { throw "No background video in current directory" }
    $BackgroundVideoPath = $latest.FullName
    Stamp "背景動画（自動）: $BackgroundVideoPath"
  } else {
    Stamp "背景動画（指定）: $BackgroundVideoPath"
  }

  $bg = (Resolve-Path $BackgroundVideoPath).Path

  # ===== オーバーレイ動画 =====
  if ([string]::IsNullOrWhiteSpace($OverlayVideoPath)) {
    $OverlayVideoPath = Pick-RandomOverlay $OverlayRoot $OverlayFrom
    Stamp "オーバーレイ（自動 $OverlayFrom）: $OverlayVideoPath"
  } else {
    Stamp "オーバーレイ（指定）: $OverlayVideoPath"
  }

  $ov = (Resolve-Path $OverlayVideoPath).Path

  # ===== バックアップ =====
  $dir  = Split-Path $bg -Parent
  $base = [IO.Path]::GetFileNameWithoutExtension($bg)
  $ext  = [IO.Path]::GetExtension($bg)
  $ts   = Get-Date -Format yyyyMMddHHmmss

  $backup = Join-Path $dir ("{0}_backup_{1}{2}" -f $base,$ts,$ext)
  Copy-Item -LiteralPath $bg -Destination $backup -Force
  Stamp "バックアップ作成: $backup"

  # ===== filter_complex =====
  $filter =
    "[1:v][0:v]scale2ref=w=main_w*{0}:h=main_w*{0}[ovl][base];" -f $OverlayRatio +
    "[ovl]format=yuva420p,colorchannelmixer=aa={0}[ovla];" -f $OverlayAlpha +
    "[base][ovla]overlay={0}:{0}:format=auto[vout]" -f $Margin

  # ===== ffmpeg（入力＝バックアップ、出力＝元ファイル名）=====
  $args = @(
    "-y",
    "-i", $backup,
    "-stream_loop","-1","-i", $ov,
    "-filter_complex", $filter,
    "-map","[vout]","-map","0:a?",
    "-shortest",
    "-c:v","libx264","-preset","ultrafast","-crf","28",
    "-pix_fmt","yuv420p",
    "-c:a","copy",
    "-movflags","+faststart",
    $bg
  )

  Stamp "ffmpeg 開始（上書き生成）"
  $p = Start-Process ffmpeg -NoNewWindow -Wait -PassThru -ArgumentList $args
  if ($p.ExitCode -ne 0) { throw "ffmpeg failed (ExitCode=$($p.ExitCode))" }

  Write-Host ""
  Write-Host "? 完了"
  Write-Host "   - 出力ファイル: $bg（元と同名）"
  Write-Host "   - バックアップ: $backup"
  Write-Host ("   - サイズ: 背景横幅の{0:P0}×{0:P0}" -f $OverlayRatio)
  Write-Host "   - 透過: $OverlayAlpha / マージン: $Margin px"
}
finally {
  $sw.Stop()
  $e = $sw.Elapsed
  Write-Host ("処理時間: {0:00}:{1:00}:{2:00}.{3:000}" -f [int]$e.TotalHours,$e.Minutes,$e.Seconds,$e.Milliseconds)
}
