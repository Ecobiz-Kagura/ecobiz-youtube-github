# =====================================================================
# charamin-overlay2.ps1（完全版 / PS5.1対応）
#  - 二重オーバーレイ防止：wide原本を一度だけ退避し、常に原本から合成
#
# 使い方:
#   .\charamin-overlay2.ps1 setup.ps1 wide.mp4 epilogue
# =====================================================================

param(
  [Parameter(Mandatory=$true)][string]$SetupScriptPath,
  [Parameter(Mandatory=$true)][string]$WideMp4,     # ユーザー指定の *_wide.mp4（最終的に同名上書きされる）

  [Parameter(Mandatory=$false)]
  [ValidateSet("none","epilogue","silent","twilight","ghost","dark")]
  [string]$BgmMode = "none",

  [double]$Opacity = 0.5,
  [int]$OutW = 1920,
  [int]$OutH = 1080,
  [int]$WaitSec = 1200
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

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

# ---- tools ----
$ffmpeg  = Get-ToolPath "ffmpeg"
$ffprobe = Get-ToolPath "ffprobe"

# ---- normalize ----
Assert-File $SetupScriptPath
Assert-File $WideMp4
$SetupScriptPath = (Resolve-Path -LiteralPath $SetupScriptPath).Path
$WideMp4         = (Resolve-Path -LiteralPath $WideMp4).Path
$ScriptRoot      = Split-Path -Parent $MyInvocation.MyCommand.Path

# ---- clamp ----
if ($Opacity -lt 0) { $Opacity = 0 }
if ($Opacity -gt 1) { $Opacity = 1 }

Stamp ("setup={0}" -f $SetupScriptPath)
Stamp ("wide ={0}" -f $WideMp4)
Stamp ("bgm  ={0}" -f $BgmMode)

# ---- 二重防止：wide原本を確保 ----
$wideDir  = Split-Path -Parent $WideMp4
$wideName = [IO.Path]::GetFileNameWithoutExtension($WideMp4)
$wideExt  = [IO.Path]::GetExtension($WideMp4)
$wideBase = Join-Path $wideDir ($wideName + "__base" + $wideExt)  # 例: xxx_wide__base.mp4

if (-not (Test-Path -LiteralPath $wideBase)) {
  Stamp ("SAVE wide base -> {0}" -f $wideBase)
  Copy-Item -LiteralPath $WideMp4 -Destination $wideBase -Force
} else {
  Stamp ("USE wide base -> {0}" -f $wideBase)
}

# ---- 1) run setup ----
Stamp "RUN setup..."
& powershell -NoProfile -ExecutionPolicy Bypass -File $SetupScriptPath
if ($LASTEXITCODE -ne 0) { throw ("SetupScript failed. exitcode={0}" -f $LASTEXITCODE) }

# ---- 2) resolve overlay mp4 (generated) ----
$overlayMp4 = Try-GetFinalOutPathFromSetup $SetupScriptPath
if ([string]::IsNullOrWhiteSpace($overlayMp4)) {
  $overlayMp4 = [IO.Path]::ChangeExtension($SetupScriptPath, ".mp4")
  Stamp ("WARN: finalOutPath not found. fallback overlay={0}" -f $overlayMp4)
} else {
  Stamp ("overlay(from setup)={0}" -f $overlayMp4)
}

Stamp ("WAIT overlay mp4: {0}" -f $overlayMp4)
Wait-ForFileStable -path $overlayMp4 -waitSec $WaitSec

# ---- duration by wide base (原本) ----
$duration = Get-DurationSec -ffprobePath $ffprobe -mp4 $wideBase
if ($duration -le 0) { throw ("Invalid duration: {0}" -f $duration) }
$durationStr = ("{0:0.###}" -f $duration)
Stamp ("duration(wide base)={0}s" -f $durationStr)

# ---- output overwrite WideMp4 safely ----
$outTmp = Join-Path $wideDir ("tmp_overlay_{0}.mp4" -f (Get-Random))
$outMp4 = $WideMp4
Stamp ("OUT(overwrite)={0}" -f $outMp4)

# ---- filter: input0=wide base, input1=overlay generated ----
$fc = ('[1:v]scale={0}:{1},format=rgba,colorchannelmixer=aa={2}[ovl];[0:v][ovl]overlay=(main_w-overlay_w)/2:(main_h-overlay_h)/2:format=auto' -f $OutW,$OutH,$Opacity)

# ---- audio pick ----
$baseHasAudio    = Has-Audio $ffprobe $wideBase
$overlayHasAudio = Has-Audio $ffprobe $overlayMp4

$audioMap = $null
if ($baseHasAudio) {
  $audioMap = "0:a:0"
  Stamp "AUDIO: use wide base"
} elseif ($overlayHasAudio) {
  $audioMap = "1:a:0"
  Stamp "AUDIO: use overlay(generated)"
} else {
  Stamp "AUDIO: none (no audio in both)"
}

# ---- ffmpeg args ----
$args = @(
  "-y",
  "-i", $wideBase,         # 0: wide base（原本）
  "-stream_loop","-1",
  "-i", $overlayMp4,       # 1: overlay（生成）
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

Stamp "RUN ffmpeg..."
& $ffmpeg @args
if ($LASTEXITCODE -ne 0) {
  if (Test-Path -LiteralPath $outTmp) { Remove-Item -LiteralPath $outTmp -Force -ErrorAction SilentlyContinue }
  throw ("ffmpeg failed. exitcode={0}" -f $LASTEXITCODE)
}
if (-not (Test-Path -LiteralPath $outTmp)) { throw ("ffmpeg tmp output missing: {0}" -f $outTmp) }

Stamp "REPLACE wide..."
Move-Item -LiteralPath $outTmp -Destination $outMp4 -Force

Stamp "OK overlay done (single layer)"

Invoke-BgmScript -mode $BgmMode -targetMp4 $outMp4 -scriptRoot $ScriptRoot

Stamp "DONE"
