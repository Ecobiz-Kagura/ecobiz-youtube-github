# =====================================================================
# charamin-overlay2.ps1（完全版 / PS5.1対応）
#
# 追加仕様:
#  - オーバーレイ動画は引数に応じて
#      D:\images_for_slide_show\MP4s-epilogue などから取得（ランダム）
#    もしくは SetupScript が生成した mp4 を使う（切替）
#
# 使い方例:
#   # (1) overlay はフォルダから取得（推奨）
#   .\charamin-overlay2.ps1 -SetupScriptPath .\11-joyuu-takamine-hideko.ps1 -WideMp4 "" -MakeWide `
#     -OverlaySource dir -OverlayMode epilogue -BgmMode epilogue
#
#   # (2) overlay は SetupScript の生成物を使う（従来）
#   .\charamin-overlay2.ps1 -SetupScriptPath .\11-joyuu-takamine-hideko.ps1 -WideMp4 "" -MakeWide `
#     -OverlaySource setup -BgmMode epilogue
# =====================================================================

param(
  # SetupScript（必要なら実行。overlay source=setup のとき必須）
  [string]$SetupScriptPath = "",

  # 既存wide（省略/空なら -MakeWide で生成したものを使う）
  [string]$WideMp4 = "",

  # ---- BGM ----
  [ValidateSet("none","epilogue","silent","twilight","ghost","dark")]
  [string]$BgmMode = "none",

  # ---- wide生成（最新 wav+srt → wide）----
  [switch]$MakeWide,
  [string]$WideOutName = "",
  [int]$WideW = 1920,
  [int]$WideH = 1080,
  [int]$WideFps = 30,
  [string]$WideBgColor = "black",
  [int]$WideFontSize = 13,
  [int]$WideOutline = 0,
  [int]$WideShadow = 0,
  [int]$WideMarginV = 40,
  [int]$WideAudioKbps = 192,

  # ---- overlay取得 ----
  [ValidateSet("dir","setup")]
  [string]$OverlaySource = "dir",

  [ValidateSet("epilogue","silent","twilight","ghost","dark")]
  [string]$OverlayMode = "epilogue",

  # overlay mp4 取得元ルート
  [string]$OverlayRoot = "D:\images_for_slide_show",

  # dirモードで候補が多い場合の上限（0=無制限）
  [int]$OverlayMaxCandidates = 5000,

  # ---- overlay合成設定 ----
  [double]$Opacity = 0.5,
  [int]$OutW = 1920,
  [int]$OutH = 1080,

  # ---- 待機 ----
  [int]$WaitSec = 1200
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# =========================
# 処理時間計測（必ず最後に表示）
# =========================
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$startedAt = Get-Date

function Stamp([string]$msg){
  $t = (Get-Date).ToString("HH:mm:ss")
  Write-Host ("[{0}] {1}" -f $t, $msg)
}
function Assert-File([string]$p){
  if (-not (Test-Path -LiteralPath $p)) { throw ("Not found: {0}" -f $p) }
}
function Get-ToolPath([string]$name){
  $cmd = Get-Command $name -ErrorAction SilentlyContinue
  if (-not $cmd) { throw ("{0} not found in PATH" -f $name) }
  return $cmd.Source
}
function Get-LatestFile([string]$pattern){
  Get-ChildItem -File -Filter $pattern -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
}
function To-FfmpegSubPath([string]$p){
  $full = (Resolve-Path -LiteralPath $p).Path
  $full = $full -replace '\\','/'
  $full = $full -replace '^([A-Za-z]):/','$1\:/'
  $full = $full -replace "'","''"
  return $full
}
function Get-DurationSec([string]$ffprobePath, [string]$mp4){
  $s = & $ffprobePath -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $mp4
  if (-not $s) { throw ("Failed to get duration: {0}" -f $mp4) }
  return [double]::Parse($s.Trim(), [System.Globalization.CultureInfo]::InvariantCulture)
}
function Has-Audio([string]$ffprobePath, [string]$mp4){
  $out = & $ffprobePath -v error -select_streams a:0 -show_entries stream=index -of csv=p=0 $mp4
  return -not [string]::IsNullOrWhiteSpace(($out | Select-Object -First 1))
}
function Try-GetFinalOutPathFromSetup([string]$ps1Path){
  $hit = Select-String -LiteralPath $ps1Path -Pattern '^\s*\$finalOutPath\s*=\s*"(.*\.mp4)"\s*$' -ErrorAction SilentlyContinue |
         Select-Object -First 1
  if ($hit) {
    $m = [regex]::Match($hit.Line, '^\s*\$finalOutPath\s*=\s*"(.*\.mp4)"\s*$')
    if ($m.Success) { return $m.Groups[1].Value }
  }
  return $null
}
function Wait-ForFileStable([string]$path, [int]$waitSec){
  $elapsed = 0
  while (-not (Test-Path -LiteralPath $path)) {
    Start-Sleep -Seconds 1
    $elapsed++
    if ($elapsed -ge $waitSec) { throw ("Timeout: file not found after {0}s : {1}" -f $waitSec, $path) }
  }
  $last = -1
  $same = 0
  while ($true) {
    $len = (Get-Item -LiteralPath $path).Length
    if ($len -eq $last -and $len -gt 0) {
      $same++
      if ($same -ge 2) { break }
    } else {
      $same = 0
      $last = $len
    }
    Start-Sleep -Seconds 1
    $elapsed++
    if ($elapsed -ge $waitSec) { throw ("Timeout: file not stable after {0}s : {1}" -f $waitSec, $path) }
  }
}

function Invoke-BgmScript([string]$mode, [string]$targetMp4, [string]$scriptRoot){
  if ($mode -eq "none") { Stamp "BGM: none (skip)"; return }

  $map = @{
    "epilogue" = "add-BGM-epilogue.ps1"
    "silent"   = "add-BGM-silent.ps1"
    "twilight" = "add-BGM-twilight.ps1"
    "ghost"    = "add-BGM-ghost.ps1"
    "dark"     = "add-BGM-dark.ps1"
  }
  $name = $map[$mode]
  if (-not $name) { throw ("Unknown BgmMode: {0}" -f $mode) }

  $bgmPs1 = Join-Path $scriptRoot $name
  Assert-File $bgmPs1

  Stamp ("BGM: run {0} target={1}" -f $name, $targetMp4)
  & powershell -NoProfile -ExecutionPolicy Bypass -File $bgmPs1 $targetMp4
  if ($LASTEXITCODE -ne 0) { throw ("BGM script failed ({0}). exitcode={1}" -f $name, $LASTEXITCODE) }
}

function Invoke-MakeWideFromLatestWavSrt {
  param(
    [string]$OutName,
    [int]$Width,
    [int]$Height,
    [int]$Fps,
    [string]$BgColor,
    [int]$FontSize,
    [int]$Outline,
    [int]$Shadow,
    [int]$MarginV,
    [int]$AudioKbps
  )

  $ffmpeg = Get-ToolPath "ffmpeg"

  $wav = Get-LatestFile "*.wav"
  $srt = Get-LatestFile "*.srt"
  if (-not $wav) { throw "wav が見つかりません（カレントに *.wav が必要）" }
  if (-not $srt) { throw "srt が見つかりません（カレントに *.srt が必要）" }

  # ★今回処理したテキスト（字幕）＝最終mp4名の元
  $script:UsedTextPath = $srt.FullName

  Stamp ("WAV: {0} ({1})" -f $wav.Name, $wav.LastWriteTime)
  Stamp ("SRT: {0} ({1})" -f $srt.Name, $srt.LastWriteTime)

  if ([string]::IsNullOrWhiteSpace($OutName)) {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $base  = [IO.Path]::GetFileNameWithoutExtension($wav.Name)
    $OutName = ("{0}_{1}_wide.mp4" -f $stamp, $base)
  }

  $outPath = Join-Path (Get-Location) $OutName

  $srtF = To-FfmpegSubPath $srt.FullName
  $forceStyle = ("Fontsize={0},Outline={1},Shadow={2},MarginV={3}" -f $FontSize,$Outline,$Shadow,$MarginV)
  $vf = ("subtitles='{0}':charenc=UTF-8:force_style='{1}'" -f $srtF, $forceStyle)

  if ([string]::IsNullOrWhiteSpace($BgColor)) { $BgColor = "black" }
  $colorSrc = ("color=c={0}:s={1}x{2}:r={3}" -f $BgColor, $Width, $Height, $Fps)
  $aBitrate = ("{0}k" -f $AudioKbps)

  Stamp ("MAKE-WIDE OUT: {0}" -f $outPath)

  $cmd = @(
    $ffmpeg,
    "-y",
    "-f","lavfi","-i",$colorSrc,
    "-i",$wav.FullName,
    "-vf",$vf,
    "-shortest",
    "-c:v","libx264",
    "-pix_fmt","yuv420p",
    "-profile:v","high",
    "-level","4.2",
    "-c:a","aac",
    "-b:a",$aBitrate,
    "-movflags","+faststart",
    $outPath
  )

  & $cmd[0] $cmd[1..($cmd.Count-1)]
  if ($LASTEXITCODE -ne 0) { throw ("make-wide ffmpeg failed. exitcode={0}" -f $LASTEXITCODE) }

  Assert-File $outPath
  return (Resolve-Path -LiteralPath $outPath).Path
}

function Get-OverlayFromDir {
  param(
    [Parameter(Mandatory=$true)][string]$Root,
    [Parameter(Mandatory=$true)][string]$Mode,
    [int]$MaxCandidates
  )
  $dir = Join-Path $Root ("MP4s-{0}" -f $Mode)
  if (-not (Test-Path -LiteralPath $dir)) {
    throw ("overlay dir not found: {0}" -f $dir)
  }

  # 直下＋サブフォルダも拾う（多い場合は上限）
  $files = Get-ChildItem -LiteralPath $dir -File -Recurse -Filter "*.mp4" -ErrorAction SilentlyContinue
  if (-not $files -or @($files).Count -eq 0) {
    throw ("overlay mp4 not found under: {0}" -f $dir)
  }

  if ($MaxCandidates -gt 0 -and @($files).Count -gt $MaxCandidates) {
    $files = $files | Select-Object -First $MaxCandidates
  }

  $pick = $files | Get-Random
  return (Resolve-Path -LiteralPath $pick.FullName).Path
}

try {
  $ffmpeg  = Get-ToolPath "ffmpeg"
  $ffprobe = Get-ToolPath "ffprobe"

  $ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

  if ($Opacity -lt 0) { $Opacity = 0 }
  if ($Opacity -gt 1) { $Opacity = 1 }

  # ============================================================
  # STEP0: wide 入力を確定（必要なら生成）
  # ============================================================
  if ($MakeWide -or [string]::IsNullOrWhiteSpace($WideMp4)) {
    Stamp "STEP0: make wide from latest wav+srt"
    $WideMp4 = Invoke-MakeWideFromLatestWavSrt `
      -OutName $WideOutName `
      -Width $WideW -Height $WideH -Fps $WideFps -BgColor $WideBgColor `
      -FontSize $WideFontSize -Outline $WideOutline -Shadow $WideShadow -MarginV $WideMarginV `
      -AudioKbps $WideAudioKbps
  } else {
    Assert-File $WideMp4
    $WideMp4 = (Resolve-Path -LiteralPath $WideMp4).Path

    # 既存wideを使う場合：同名srtがあるならそれを最終名の元として採用
    $sameSrt = [IO.Path]::ChangeExtension($WideMp4, ".srt")
    if (Test-Path -LiteralPath $sameSrt) {
      $script:UsedTextPath = (Resolve-Path -LiteralPath $sameSrt).Path
      Stamp ("TEXT: use same-name srt -> {0}" -f $script:UsedTextPath)
    }
  }

  Stamp ("wide ={0}" -f $WideMp4)
  Stamp ("overlaySource={0} overlayMode={1}" -f $OverlaySource, $OverlayMode)
  Stamp ("bgm  ={0}" -f $BgmMode)

  # ============================================================
  # STEP1: wide原本(__base)を確保（二重防止）
  # ============================================================
  $wideDir  = Split-Path -Parent $WideMp4
  $wideName = [IO.Path]::GetFileNameWithoutExtension($WideMp4)
  $wideExt  = [IO.Path]::GetExtension($WideMp4)
  $wideBase = Join-Path $wideDir ($wideName + "__base" + $wideExt)

  if (-not (Test-Path -LiteralPath $wideBase)) {
    Stamp ("SAVE wide base -> {0}" -f $wideBase)
    Copy-Item -LiteralPath $WideMp4 -Destination $wideBase -Force
  } else {
    Stamp ("USE wide base -> {0}" -f $wideBase)
  }

  # ============================================================
  # STEP2: overlay mp4 を決める（dir or setup）
  # ============================================================
  $overlayMp4 = $null

  if ($OverlaySource -eq "dir") {
    $overlayMp4 = Get-OverlayFromDir -Root $OverlayRoot -Mode $OverlayMode -MaxCandidates $OverlayMaxCandidates
    Stamp ("overlay(from dir)={0}" -f $overlayMp4)
  } else {
    if ([string]::IsNullOrWhiteSpace($SetupScriptPath)) {
      throw "OverlaySource=setup なのに SetupScriptPath が空です。"
    }
    Assert-File $SetupScriptPath
    $SetupScriptPath = (Resolve-Path -LiteralPath $SetupScriptPath).Path

    Stamp ("STEP2: run setup... {0}" -f $SetupScriptPath)
    & powershell -NoProfile -ExecutionPolicy Bypass -File $SetupScriptPath
    if ($LASTEXITCODE -ne 0) { throw ("SetupScript failed. exitcode={0}" -f $LASTEXITCODE) }

    $overlayMp4 = Try-GetFinalOutPathFromSetup $SetupScriptPath
    if ([string]::IsNullOrWhiteSpace($overlayMp4)) {
      $overlayMp4 = [IO.Path]::ChangeExtension($SetupScriptPath, ".mp4")
      Stamp ("WARN: finalOutPath not found. fallback overlay={0}" -f $overlayMp4)
    } else {
      Stamp ("overlay(from setup)={0}" -f $overlayMp4)
    }

    Stamp ("WAIT overlay mp4: {0}" -f $overlayMp4)
    Wait-ForFileStable -path $overlayMp4 -waitSec $WaitSec
    $overlayMp4 = (Resolve-Path -LiteralPath $overlayMp4).Path
  }

  Assert-File $overlayMp4

  # ============================================================
  # STEP3: 1回だけ合成（wide原本に対して）
  # ============================================================
  $duration = Get-DurationSec -ffprobePath $ffprobe -mp4 $wideBase
  $durationStr = ("{0:0.###}" -f $duration)

  # 最終出力名：処理したテキスト（基本SRT）と同名（拡張子 .mp4）★_wide無し
  $outMp4 = $WideMp4
  if ($script:UsedTextPath) {
    $bn = [IO.Path]::GetFileNameWithoutExtension($script:UsedTextPath)
    $outMp4 = Join-Path $wideDir ($bn + ".mp4")
    Stamp ("FINAL NAME from text: {0}" -f $outMp4)
  } else {
    Stamp "WARN: UsedTextPath not set. fallback to wide name."
  }

  $outTmp = Join-Path $wideDir ("tmp_overlay_{0}.mp4" -f (Get-Random))

  $fc = ('[1:v]scale={0}:{1},format=rgba,colorchannelmixer=aa={2}[ovl];[0:v][ovl]overlay=(main_w-overlay_w)/2:(main_h-overlay_h)/2:format=auto' -f $OutW,$OutH,$Opacity)

  $baseHasAudio    = Has-Audio $ffprobe $wideBase
  $overlayHasAudio = Has-Audio $ffprobe $overlayMp4
  $audioMap = $null
  if ($baseHasAudio) { $audioMap = "0:a:0"; Stamp "AUDIO: use wide base" }
  elseif ($overlayHasAudio) { $audioMap = "1:a:0"; Stamp "AUDIO: use overlay(mp4)" }
  else { Stamp "AUDIO: none" }

  $args = @(
    "-y",
    "-i", $wideBase,
    "-stream_loop","-1",
    "-i", $overlayMp4,
    "-filter_complex", $fc,
    "-map", "0:v:0"
  )
  if ($audioMap) { $args += @("-map", $audioMap) }

  $args += @(
    "-t", $durationStr,
    "-c:v","libx264",
    "-pix_fmt","yuv420p",
    "-c:a","aac",
    "-movflags","+faststart",
    $outTmp
  )

  Stamp "STEP3: run ffmpeg overlay..."
  & $ffmpeg @args
  if ($LASTEXITCODE -ne 0) {
    if (Test-Path -LiteralPath $outTmp) { Remove-Item -LiteralPath $outTmp -Force -ErrorAction SilentlyContinue }
    throw ("ffmpeg failed. exitcode={0}" -f $LASTEXITCODE)
  }

  if (Test-Path -LiteralPath $outMp4) {
    Remove-Item -LiteralPath $outMp4 -Force -ErrorAction SilentlyContinue
  }
  Stamp ("STEP3: save -> {0}" -f $outMp4)
  Move-Item -LiteralPath $outTmp -Destination $outMp4 -Force
  Stamp "OK overlay done (single layer)"

  # ============================================================
  # STEP4: BGM
  # ============================================================
  Invoke-BgmScript -mode $BgmMode -targetMp4 $outMp4 -scriptRoot $ScriptRoot
  Stamp "DONE"
}
finally {
  $sw.Stop()
  $elapsed = $sw.Elapsed
  $totalSec = [math]::Round($elapsed.TotalSeconds, 1)
  $mmss = "{0:mm\:ss}" -f $elapsed

  Write-Host ""
  Write-Host "========================="
  Write-Host ("開始時刻 : {0}" -f $startedAt)
  Write-Host ("終了時刻 : {0}" -f (Get-Date))
  Write-Host ("処理時間 : {0} 秒 ({1})" -f $totalSec, $mmss)
  Write-Host "========================="
}
