# =====================================================================
# overlay11.ps1（完全版：dark / light を引数化・フォルダ先頭集約）
# 確認なしで実行する版
# 実行形式は変更しない：
#   .\overlay11.ps1 -OverlayTheme dark -OverlayFrom left
# =====================================================================

param(
  # 背景動画（省略可：カレント直下の最新動画）
  [string]$BackgroundVideoPath,

  # オーバーレイ動画（省略可：自動選択）
  [string]$OverlayVideoPath,

  # ★テーマ（dark / light）
  [ValidateSet("dark","light","epilogue")]
  [string]$OverlayTheme = "dark",

  # ★位置（left / right / center）
  [ValidateSet("left","right","center")]
  [string]$OverlayFrom = "left",

  # 互換用（使わなくてもよい）
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

# =====================================================
# ★ オーバーレイ動画フォルダ設定（先頭集約）
# =====================================================
$OverlayFolderMap = @{
    "dark-left"   = "D:\images_for_slide_show\MP4s-dark\left"
    "dark-right"  = "D:\images_for_slide_show\MP4s-dark\right"
    "dark-center" = "D:\images_for_slide_show\MP4s-dark\center"

    "epilogue-left"   = "D:\images_for_slide_show\MP4s-epilogue\left"
    "epilogue-right"  = "D:\images_for_slide_show\MP4s-epilogue\right"
    "epilogue-center" = "D:\images_for_slide_show\MP4s-epilogue\center"

    "silent-left"   = "D:\images_for_slide_show\MP4s-light\left"
    "silent-right"  = "D:\images_for_slide_show\MP4s-light\right"
    "silent-center" = "D:\images_for_slide_show\MP4s-light\center"
}

# ========= タイマー =========
$sw = [System.Diagnostics.Stopwatch]::StartNew()
function Stamp([string]$msg){
  Write-Host ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $msg)
}

function Assert-File([string]$p){
  if ([string]::IsNullOrWhiteSpace($p)) { throw "Empty path" }
  if (-not (Test-Path -LiteralPath $p)) { throw ("Not found: {0}" -f $p) }
}

# 最新動画（カレント直下）
function Get-LatestVideoInCwd([string[]]$exts){
  $cwd = (Get-Location).Path
  $files = foreach ($e in $exts) {
    Get-ChildItem -LiteralPath $cwd -File -Filter $e -ErrorAction SilentlyContinue
  }
  $files | Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

# オーバーレイ動画取得（先頭Map優先／互換fallbackあり）
function Pick-RandomOverlay([string]$base, [string]$theme, [string]$from){

  $key = "$theme-$from"

  if ($OverlayFolderMap.ContainsKey($key)) {
    $dir = $OverlayFolderMap[$key]
  }
  else {
    $root = Join-Path $base ("MP4s-{0}" -f $theme)
    $dir  = Join-Path $root $from
  }

  if (-not (Test-Path -LiteralPath $dir)) {
    throw "オーバーレイ取得先が見つかりません: $dir"
  }

  $cands = Get-ChildItem -LiteralPath $dir -File -Filter *.mp4
  if (-not $cands) {
    throw "オーバーレイ動画がありません: $dir"
  }

  return ($cands | Get-Random).FullName
}

try {
  if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    throw "ffmpeg が見つかりません（PATH を確認）"
  }

  # ===== 背景動画 =====
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

  # ===== オーバーレイ動画 =====
  if ([string]::IsNullOrWhiteSpace($OverlayVideoPath)) {
    $OverlayVideoPath = Pick-RandomOverlay -base $OverlayRootBase -theme $OverlayTheme -from $OverlayFrom
    Stamp "オーバーレイ（自動）: theme=$OverlayTheme from=$OverlayFrom → $OverlayVideoPath"
  } else {
    Stamp "オーバーレイ（指定）: $OverlayVideoPath"
  }
  Assert-File $OverlayVideoPath
  $ov = (Resolve-Path -LiteralPath $OverlayVideoPath).Path

  # ===== バックアップ =====
  $dir  = Split-Path $bg -Parent
  $base = [IO.Path]::GetFileNameWithoutExtension($bg)
  $ext  = [IO.Path]::GetExtension($bg)
  $ts   = Get-Date -Format "yyyyMMddHHmmss"
  $backup = Join-Path $dir ("{0}_backup_{1}{2}" -f $base,$ts,$ext)

  Copy-Item -LiteralPath $bg -Destination $backup -Force
  Stamp "バックアップ作成: $backup"

  # ===== filter_complex =====
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

  # 実行コマンド表示（確認なし）
  $parts = $ffArgs | ForEach-Object {
    if ($_ -match '\s') { '"' + ($_ -replace '"','\"') + '"' } else { $_ }
  }
  Write-Host ""
  Write-Host "[CMD] ffmpeg " + ($parts -join ' ')

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
