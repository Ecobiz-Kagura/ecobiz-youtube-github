# =====================================================================
# overlay11.ps1（完全版：dark / light / epilogue を引数化・フォルダ先頭集約）
# 確認なしで実行する版（実行形式は変更しない）
#   .\overlay11.ps1 -OverlayTheme dark -OverlayFrom left
# =====================================================================

param(
  # 背景動画（省略可：カレント直下の最新動画）
  [string]$BackgroundVideoPath,

  # オーバーレイ動画（省略可：自動選択）
  [string]$OverlayVideoPath,

  # テーマ
  [ValidateSet("dark","light","epilogue")]
  [string]$OverlayTheme = "dark",

  # 位置
  [ValidateSet("left","right","center")]
  [string]$OverlayFrom = "left",

  # 互換用（使わなくてもよい）
  [string]$OverlayRootBase = "D:\images_for_slide_show",

  # マージン(px)
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
  # dark
  "dark-left"    = "D:\images_for_slide_show\MP4s-dark\left"
  "dark-right"   = "D:\images_for_slide_show\MP4s-dark\right"
  "dark-center"  = "D:\images_for_slide_show\MP4s-dark\center"

  # light
  "light-left"   = "D:\images_for_slide_show\MP4s-light\left"
  "light-right"  = "D:\images_for_slide_show\MP4s-light\right"
  "light-center" = "D:\images_for_slide_show\MP4s-light\center"

  # epilogue
  "epilogue-left"   = "D:\images_for_slide_show\MP4s-epilogue\left"
  "epilogue-right"  = "D:\images_for_slide_show\MP4s-epilogue\right"
  "epilogue-center" = "D:\images_for_slide_show\MP4s-epilogue\center"
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

  $cands = Get-ChildItem -LiteralPath $dir -File -Filter *.mp4 -ErrorAction SilentlyContinue
  if (-not $cands) {
    throw "オーバーレイ動画がありません: $dir"
  }

  return ($cands | Get-Random).FullName
}

# ffprobe で duration(秒) を取得（安定化用：-shortest を使わない）
function Get-DurationSec([string]$path){
  $out = & ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 $path 2>$null
  if(-not $out){ throw "ffprobe で duration を取得できません: $path" }
  $d = [double]($out.Trim())
  if($d -le 0){ throw "duration が不正です: $d ($path)" }
  return $d
}

# 位置に応じた overlay x,y を返す（y は margin 固定、x は left/right/center）
# ※ overlay の幅は scale2ref の main_w*OverlayRatio に一致する前提
function Get-OverlayXY([string]$from, [int]$margin){
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

  # ===== 背景の尺（-t に使う：無限ループ + -shortest のクラッシュ回避） =====
  $dur = Get-DurationSec $backup
  Stamp ("背景の長さ: {0:F3} 秒" -f $dur)

  # ===== overlay 座標 =====
  $xy = Get-OverlayXY -from $OverlayFrom -margin $Margin
  $x = $xy[0]
  $y = $xy[1]

  # ===== filter_complex =====
  # 1) overlay を base 幅比で scale（scale2ref）
  # 2) overlay を yuva + alpha
  # 3) base に overlay（位置は left/right/center）
  $filter =
    ("[1:v][0:v]scale2ref=w=main_w*{0}:h=main_w*{0}[ovl][base];" -f $OverlayRatio) +
    ("[ovl]format=yuva420p,colorchannelmixer=aa={0}[ovla];" -f $OverlayAlpha) +
    ("[base][ovla]overlay=x={0}:y={1}:format=auto[vout]" -f $x, $y)

  # ===== ffmpeg =====
  # -stream_loop -1 は維持（素材を途切れさせない）
  # ただし終了条件は -shortest ではなく -t (背景尺) で明確化（安定化）
  $ffArgs = @(
    "-y",
    "-i", $backup,
    "-stream_loop","-1","-i", $ov,
    "-filter_complex", $filter,
    "-map","[vout]","-map","0:a?",
    "-t", ("{0:F3}" -f $dur),
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
  Write-Host "完了"
  Write-Host "  - 出力: $bg（元と同名）"
  Write-Host "  - バックアップ: $backup"
  Write-Host ("  - サイズ: 背景横幅の{0:P0}×{0:P0}" -f $OverlayRatio)
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
  Write-Host ("処理時間: {0:00}:{1:00}:{2:00}.{3:000}" -f [int]$e.TotalHours,$e.Minutes,$e.Seconds,$e.Milliseconds)
}
