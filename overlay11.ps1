# =====================================================================
# overlay11.ps1（完全版：dark / light を引数化）
# =====================================================================

param(
  # 背景動画（省略可：カレント直下の最新動画）
  [string]$BackgroundVideoPath,

  # オーバーレイ動画（省略可：Theme+From で自動取得）
  [string]$OverlayVideoPath,

  # ★テーマ（dark / light）
  [ValidateSet("dark","light")]
  [string]$OverlayTheme = "dark",

  # ★位置（left / right / center）
  [ValidateSet("left","right","center")]
  [string]$OverlayFrom = "left",

  # オーバーレイルート（テーマの親）
  [string]$OverlayRootBase = "D:\images_for_slide_show",

  # 左上マージン(px)
  [int]$Margin = 10,

  # 透過度（1.0=不透明）
  [ValidateRange(0.0, 1.0)]
  [double]$OverlayAlpha = 0.6,

  # 背景横幅に対する比率（0.3=30%）
  [ValidateRange(0.01, 1.0)]
  [double]$OverlayRatio = 0.3,

  # 最新背景の検索対象拡張子
  [string[]]$BackgroundExts = @("*.mp4","*.mov","*.mkv","*.webm")

)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ========= タイマー =========
$sw = [System.Diagnostics.Stopwatch]::StartNew()
function Stamp([string]$msg){
  Write-Host ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $msg)
}

function Assert-File([string]$p){
  if ([string]::IsNullOrWhiteSpace($p)) { throw "Empty path" }
  if (-not (Test-Path -LiteralPath $p)) { throw ("Not found: {0}" -f $p) }
}

# foreach → 変数 → パイプ（ParserError 回避）
function Get-LatestVideoInCwd([string[]]$exts){
  $cwd = (Get-Location).Path
  $files = foreach ($e in $exts) {
    Get-ChildItem -LiteralPath $cwd -File -Filter $e -ErrorAction SilentlyContinue
  }
  $files | Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

function Pick-RandomOverlay([string]$base, [string]$theme, [string]$from){
  $root = Join-Path $base ("MP4s-{0}" -f $theme)
  $dir  = Join-Path $root $from
  if (-not (Test-Path -LiteralPath $dir)) {
    throw "オーバーレイ取得先が見つかりません: $dir"
  }
  $cands = Get-ChildItem -LiteralPath $dir -File -Filter *.mp4 -ErrorAction SilentlyContinue
  if (-not $cands -or $cands.Count -eq 0) {
    throw "オーバーレイ動画がありません: $dir"
  }
  ($cands | Get-Random).FullName
}

try {
  if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    throw "ffmpeg が見つかりません（PATH を確認）"
  }

  # ===== 背景動画 =====
  if ([string]::IsNullOrWhiteSpace($BackgroundVideoPath)) {
    $latest = Get-LatestVideoInCwd -exts $BackgroundExts
    if (-not $latest) {
      throw "カレントディレクトリに動画がありません: $((Get-Location).Path)"
    }
    $BackgroundVideoPath = $latest.FullName
    Stamp "背景動画（自動）: $BackgroundVideoPath"
  } else {
    Stamp "背景動画（指定）: $BackgroundVideoPath"
  }
  Assert-File $BackgroundVideoPath
  $bg = (Resolve-Path -LiteralPath $BackgroundVideoPath).Path

  # ===== オーバーレイ動画 =====
  if ([string]::IsNullOrWhiteSpace($OverlayVideoPath)) {
    $OverlayVideoPath = Pick-RandomOverlay -base $OverlayRootBase -theme $OverlayTheme -from $OverlayFrom
    Stamp "オーバーレイ（自動）: theme=$OverlayTheme from=$OverlayFrom → $OverlayVideoPath"
  } else {
    Stamp "オーバーレイ（指定）: $OverlayVideoPath"
  }
  Assert-File $OverlayVideoPath
  $ov = (Resolve-Path -LiteralPath $OverlayVideoPath).Path

  # ===== バックアップ（入力はバックアップ、出力は元名）=====
  $dir  = Split-Path $bg -Parent
  $base = [IO.Path]::GetFileNameWithoutExtension($bg)
  $ext  = [IO.Path]::GetExtension($bg)
  $ts   = Get-Date -Format "yyyyMMddHHmmss"
  $backup = Join-Path $dir ("{0}_backup_{1}{2}" -f $base,$ts,$ext)

  Copy-Item -LiteralPath $bg -Destination $backup -Force
  Stamp "バックアップ作成: $backup"

  # ===== filter_complex（正方形に引き伸ばし）=====
  $filter =
    ("[1:v][0:v]scale2ref=w=main_w*{0}:h=main_w*{0}[ovl][base];" -f $OverlayRatio) +
    ("[ovl]format=yuva420p,colorchannelmixer=aa={0}[ovla];" -f $OverlayAlpha) +
    ("[base][ovla]overlay={0}:{0}:format=auto[vout]" -f $Margin)

  # ===== ffmpeg =====
  $ffArgs = @(
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

  Stamp "ffmpeg 開始（出力は元と同名）"
  $p = Start-Process -NoNewWindow -PassThru -Wait -FilePath "ffmpeg" -ArgumentList $ffArgs
  if ($p.ExitCode -ne 0) { throw "ffmpeg 失敗 (ExitCode=$($p.ExitCode))" }

  Write-Host ""
  Write-Host "? 完了"
  Write-Host "   - 出力: $bg（元と同名）"
  Write-Host "   - バックアップ: $backup"
  Write-Host ("   - サイズ: 背景横幅の{0:P0}×{0:P0}" -f $OverlayRatio)
  Write-Host "   - Theme/From: $OverlayTheme / $OverlayFrom"
}
catch {
  Write-Error $_
  exit 1
}
finally {
  $sw.Stop()
  $e = $sw.Elapsed
  Write-Host ("処理時間: {0:00}:{1:00}:{2:00}.{3:000}" -f [int]$e.TotalHours,$e.Minutes,$e.Seconds,$e.Milliseconds)
}
