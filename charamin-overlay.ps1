# =====================================================================
# charamin-overlay.ps1（完全版 / PS5.1対応）
#
# 使い方:
#   .\charamin-overlay.ps1 .\11-joyuu-takamine-hideko.ps1 .\xxxx_wide.mp4
#
# 挙動:
#   1) SetupScript を実行して生成動画を作る
#   2) wide(mp4) を背景（オーバーレイされる側 / base）
#   3) 生成動画(mp4) をオーバーレイする側 / overlay（ループ）
#   4) 出力は wide と同名で安全に上書き（tmp → Move）
#
# 重要:
#   - 生成動画のパスは SetupScript 内の $finalOutPath を優先して取得
#     見つからなければ SetupScript と同名 .mp4 をフォールバック
#   - PowerShell 5.1 互換（?. 等は不使用）
# =====================================================================

param(
  [Parameter(Mandatory=$true)][string]$SetupScriptPath,
  [Parameter(Mandatory=$true)][string]$BaseMp4,   # ← wide を渡す（背景）

  [double]$Opacity = 0.5,
  [int]$OutW = 1920,
  [int]$OutH = 1080,

  # 生成待ち最大秒（無限待ち防止）
  [int]$WaitSec = 1200
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Stamp([string]$msg){
  $t = (Get-Date).ToString("HH:mm:ss")
  Write-Host ("[{0}] {1}" -f $t, $msg)
}
function Assert-File([string]$p){
  if (-not (Test-Path -LiteralPath $p)) { throw "Not found: $p" }
}
function Get-ToolPath([string]$name){
  $cmd = Get-Command $name -ErrorAction SilentlyContinue
  if (-not $cmd) { throw "$name not found in PATH" }
  return $cmd.Source
}
function Get-DurationSec([string]$ffprobePath, [string]$mp4){
  $s = & $ffprobePath -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $mp4
  if (-not $s) { throw "Failed to get duration: $mp4" }
  return [double]::Parse($s.Trim(), [System.Globalization.CultureInfo]::InvariantCulture)
}

function Try-GetFinalOutPathFromSetup([string]$ps1Path){
  # $finalOutPath = "....mp4" の行を拾う（簡易）
  # ※ あなたの setup はこの形式なのでこれで十分
  $hit = Select-String -LiteralPath $ps1Path -Pattern '^\s*\$finalOutPath\s*=\s*"(.*\.mp4)"\s*$' -ErrorAction SilentlyContinue |
         Select-Object -First 1
  if ($hit) {
    $m = [regex]::Match($hit.Line, '^\s*\$finalOutPath\s*=\s*"(.*\.mp4)"\s*$')
    if ($m.Success) { return $m.Groups[1].Value }
  }
  return $null
}

function Wait-ForFileStable([string]$path, [int]$waitSec){
  # 存在するまで待つ → サイズが2回連続で同じになったら「書き込み完了」とみなす
  $elapsed = 0
  while (-not (Test-Path -LiteralPath $path)) {
    Start-Sleep -Seconds 1
    $elapsed++
    if ($elapsed -ge $waitSec) { throw "Timeout: file not found after ${waitSec}s : $path" }
  }

  $last = -1
  $same = 0
  while ($true) {
    $len = (Get-Item -LiteralPath $path).Length
    if ($len -eq $last -and $len -gt 0) {
      $same++
      if ($same -ge 2) { break }   # 2秒連続で変化なし
    } else {
      $same = 0
      $last = $len
    }
    Start-Sleep -Seconds 1
    $elapsed++
    if ($elapsed -ge $waitSec) { throw "Timeout: file not stable after ${waitSec}s : $path" }
  }
}

# ---- tools ----
$ffmpeg  = Get-ToolPath "ffmpeg"
$ffprobe = Get-ToolPath "ffprobe"

# ---- normalize ----
Assert-File $SetupScriptPath
Assert-File $BaseMp4
$SetupScriptPath = (Resolve-Path -LiteralPath $SetupScriptPath).Path
$BaseMp4         = (Resolve-Path -LiteralPath $BaseMp4).Path

# ---- opacity clamp ----
if ($Opacity -lt 0) { $Opacity = 0 }
if ($Opacity -gt 1) { $Opacity = 1 }

Stamp ("setup  = {0}" -f $SetupScriptPath)
Stamp ("base   = {0}" -f $BaseMp4)
Stamp ("ffmpeg = {0}" -f $ffmpeg)
Stamp ("ffprobe= {0}" -f $ffprobe)

# ---- 1) run setup ----
Stamp "RUN setup script..."
& powershell -NoProfile -ExecutionPolicy Bypass -File $SetupScriptPath
if ($LASTEXITCODE -ne 0) { throw "SetupScript failed. exitcode=$LASTEXITCODE" }

# ---- 2) resolve overlay mp4 (generated) ----
$overlayMp4 = Try-GetFinalOutPathFromSetup $SetupScriptPath
if ([string]::IsNullOrWhiteSpace($overlayMp4)) {
  $overlayMp4 = [IO.Path]::ChangeExtension($SetupScriptPath, ".mp4")
  Stamp ("[WARN] $finalOutPath not found in setup. fallback overlay={0}" -f $overlayMp4)
} else {
  Stamp ("overlay from setup finalOutPath = {0}" -f $overlayMp4)
}

# ---- 3) wait for generated mp4 ----
Stamp ("WAIT overlay mp4: {0}" -f $overlayMp4)
Wait-ForFileStable -path $overlayMp4 -waitSec $WaitSec

# ---- 4) duration by base(wide) ----
$duration = Get-DurationSec -ffprobePath $ffprobe -mp4 $BaseMp4
if ($duration -le 0) { throw "Invalid duration: $duration" }
$durationStr = ("{0:0.###}" -f $duration)
Stamp ("duration(base) = {0}s" -f $durationStr)

# ---- 5) output: overwrite base safely (tmp -> move) ----
$outDir = Split-Path -Parent $BaseMp4
$outTmp = Join-Path $outDir ("tmp_overlay_{0}.mp4" -f (Get-Random))
$outMp4 = $BaseMp4

Stamp ("OUT(overwrite) = {0}" -f $outMp4)

# ---- filter: input0=base(wide), input1=overlay(generated) ----
$fc = "[1:v]scale=${OutW}:${OutH},format=rgba,colorchannelmixer=aa=${Opacity}[ovl];" +
      "[0:v][ovl]overlay=(main_w-overlay_w)/2:(main_h-overlay_h)/2:format=auto"

# ---- run ffmpeg to tmp ----
$args = @(
  "-y",
  "-i", $BaseMp4,
  "-stream_loop", "-1",
  "-i", $overlayMp4,
  "-filter_complex", $fc,
  "-map", "0:v:0",
  "-map", "0:a?",
  "-t", $durationStr,
  "-c:v", "libx264",
  "-pix_fmt", "yuv420p",
  "-c:a", "aac",
  "-movflags", "+faststart",
  $outTmp
)

Stamp "RUN ffmpeg (tmp output)..."
& $ffmpeg @args
if ($LASTEXITCODE -ne 0) {
  if (Test-Path -LiteralPath $outTmp) { Remove-Item -LiteralPath $outTmp -Force }
  throw "ffmpeg failed. exitcode=$LASTEXITCODE"
}
if (-not (Test-Path -LiteralPath $outTmp)) { throw "ffmpeg tmp output missing: $outTmp" }

# ---- atomic-ish replace ----
Stamp "REPLACE base (overwrite)..."
try {
  Move-Item -LiteralPath $outTmp -Destination $outMp4 -Force
} catch {
  if (Test-Path -LiteralPath $outTmp) { Remove-Item -LiteralPath $outTmp -Force }
  throw
}

Stamp "[OK] 完了"
