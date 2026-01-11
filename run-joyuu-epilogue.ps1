# encoding: UTF-8
param (
    [Parameter(Mandatory = $true)][string]$textFilePath,        # 例: .\20250511220157-159-....txt
    [Parameter(Mandatory = $true)][string]$overlayVideoPath     # 例: .\10-bio-2.mp4
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# =========================
# 共通: ffmpeg
# =========================
$FFMPEG = 'D:\ffmpeg.exe'

function Ensure-Dir([string]$p){
  if (-not (Test-Path -LiteralPath $p)) {
    New-Item -ItemType Directory -Path $p -Force | Out-Null
  }
}

function Write-Utf8NoBomLines([string]$path, [string[]]$lines){
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllLines($path, $lines, $utf8NoBom)
}

function Normalize-And-Concat {
  param(
    [Parameter(Mandatory=$true)][string]$SrcDir,
    [Parameter(Mandatory=$true)][string]$OutDir,
    [Parameter(Mandatory=$true)][string]$OutPrefix,
    [int]$PickCount = 5,

    # 固定仕様（素材バラバラ対策）
    [int]$W = 1280,
    [int]$H = 720,
    [int]$Fps = 30,
    [int]$Crf = 20,
    [string]$Preset = 'veryfast'
  )

  if (-not (Test-Path -LiteralPath $SrcDir)) { throw ("Source not found: {0}" -f $SrcDir) }
  Ensure-Dir $OutDir

  $mp4s = Get-ChildItem -LiteralPath $SrcDir -File -Filter *.mp4
  if ($mp4s.Count -lt $PickCount) {
    # ★ここが修正点：${} で変数名を区切る（":" 衝突回避）
    throw "MP4 が${PickCount}本未満です: $($mp4s.Count)"
  }

  $pick = $mp4s | Get-Random -Count $PickCount

  Write-Host ("=== 選択された動画 ({0}) ===" -f $OutPrefix)
  $pick | ForEach-Object { Write-Host ("  {0}" -f $_.Name) }

  # ---- 1) 正規化して同一仕様に揃える ----
  $tmpDir = Join-Path ([IO.Path]::GetTempPath()) ("norm_" + [guid]::NewGuid().ToString("N"))
  Ensure-Dir $tmpDir

  $normPaths = @()
  $i = 0
  foreach($f in $pick){
    $i++
    $norm = Join-Path $tmpDir ("norm_{0:000}.mp4" -f $i)

    $vf = "scale=${W}:${H}:force_original_aspect_ratio=decrease,pad=${W}:${H}:(ow-iw)/2:(oh-ih)/2,fps=${Fps},format=yuv420p"

    $argsN = @(
      '-y',
      '-nostdin',
      '-hide_banner',
      '-loglevel','warning',
      '-i', $f.FullName,
      '-vf', $vf,
      '-c:v','libx264',
      '-preset', $Preset,
      '-crf', $Crf,
      '-pix_fmt','yuv420p',
      '-movflags','+faststart',
      $norm
    )

    Write-Host ("[norm {0}/{1}] {2}" -f $i, $PickCount, $f.Name)
    & $FFMPEG @argsN
    if (-not (Test-Path -LiteralPath $norm)) { throw ("normalize failed: {0}" -f $norm) }

    $normPaths += $norm
  }

  # ---- 2) concat list（UTF-8 BOMなし）----
  $tmpList = Join-Path $tmpDir "concat.txt"
  $lines = $normPaths | ForEach-Object {
    $p = $_.Replace("'", "''")
    "file '$p'"
  }
  Write-Utf8NoBomLines $tmpList $lines

  # ---- 3) concat（再エンコード）----
  $outFile = Join-Path $OutDir ("{0}-{1}.mp4" -f $OutPrefix, (Get-Date -Format 'yyyyMMdd-HHmmss'))

  $argsC = @(
    '-y',
    '-nostdin',
    '-hide_banner',
    '-loglevel','warning',
    '-f','concat',
    '-safe','0',
    '-i', $tmpList,
    '-map','0:v:0',
    '-map','0:a?',

    # 仕上げも固定
    '-vf', "fps=${Fps},format=yuv420p",
    '-r',  "$Fps",

    # 音声なし		
    '-an',

    '-c:v','libx264',
    '-preset', $Preset,
    '-crf',    $Crf,
    '-pix_fmt','yuv420p',
    '-movflags','+faststart',
    $outFile
  )

  Write-Host "=== concat 実行 ==="
  & $FFMPEG @argsC

  # 後片付け
  Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue

  Write-Host ("=== 完了: {0} ===" -f $outFile)
  return $outFile
}

# =========================
# 0) 事前バックアップ
# =========================
$origLeaf = Split-Path -Leaf $textFilePath
$origBase = [IO.Path]::GetFileNameWithoutExtension($origLeaf)

$srcDir    = Split-Path -Parent $textFilePath
$backupDir = Join-Path $srcDir "_backup"
Ensure-Dir $backupDir

$ts = Get-Date -Format "yyyyMMdd-HHmmss"
$backupName = "{0}__backup__{1}{2}" -f $origBase, $ts, [IO.Path]::GetExtension($textFilePath)
Copy-Item -LiteralPath $textFilePath -Destination (Join-Path $backupDir $backupName) -Force

# =========================
# 1) ファイル名の正規化（ダッシュ/空白→"_"）
# =========================
$dir  = Split-Path -Parent $textFilePath
$leaf = Split-Path -Leaf   $textFilePath

$fixedLeaf = $leaf `
  -replace "[\u2010\u2011\u2012\u2013\u2014\u2015\u2212\u30FC\uFF0D]", "_" `
  -replace "[\s\u00A0\u3000]+", "_"

if ($leaf -ne $fixedLeaf) {
  $newPath = Join-Path $dir $fixedLeaf
  Rename-Item -LiteralPath $textFilePath -NewName $fixedLeaf
  $textFilePath = $newPath
}

# =========================
# 2) ベース名算出（mp4名）
# =========================
$baseName = [System.IO.Path]::GetFileNameWithoutExtension($textFilePath)
$mp4File  = "$baseName.mp4"

# =========================
# 3) テキスト処理
# =========================
Write-Host ("? python .\9.py {0}" -f $textFilePath)
if (Test-Path -LiteralPath ".\9.py") {
  python .\9.py $textFilePath
} else {
  Write-Warning "skip: 9.py not found."
}

# =========================
# 4) MP4 に最初のオーバーレイ
# =========================
Write-Host ("? .\overlay3.ps1 {0} {1}" -f $mp4File, $overlayVideoPath)
if (Test-Path -LiteralPath ".\overlay3.ps1") {
  .\overlay3.ps1 $mp4File $overlayVideoPath
} else {
  Write-Warning "skip: overlay3.ps1 not found."
}

# =========================
# 5) left用の素材を作る（eco / joyuu）
# =========================

# eco
Remove-Item -LiteralPath 'D:\images_for_slide_show\MP4s-epilogue\left\eco\*' -Force -ErrorAction SilentlyContinue
$ecoMerged = Normalize-And-Concat `
  -SrcDir 'D:\images_for_slide_show\MP4s-epilogue\eco-org' `
  -OutDir 'D:\images_for_slide_show\MP4s-epilogue\left\eco' `
  -OutPrefix 'eco-merge' `
  -PickCount 5 `
  -W 1280 -H 720 -Fps 30 -Crf 20 -Preset 'veryfast'

# joyuu
Remove-Item -LiteralPath 'D:\images_for_slide_show\MP4s-epilogue\left\joyuu\*' -Force -ErrorAction SilentlyContinue
$joyuuMerged = Normalize-And-Concat `
  -SrcDir 'D:\images_for_slide_show\MP4s-epilogue\joyuu-org' `
  -OutDir 'D:\images_for_slide_show\MP4s-epilogue\left\joyuu' `
  -OutPrefix 'joyuu-merge' `
  -PickCount 5 `
  -W 1280 -H 720 -Fps 30 -Crf 20 -Preset 'veryfast'

# =========================
# 6) 安全なベース名生成＆オーバーレイ差し替え（LEFT/RIGHT）
# =========================
$baseName = [IO.Path]::GetFileNameWithoutExtension($textFilePath)
$safeBase = $baseName -replace "[\s\u00A0\u3000\u3002\uFF0E\.]+$",""

$mp4Dir  = Split-Path -Parent $textFilePath
$mp4File = Join-Path $mp4Dir "$safeBase.mp4"
if ($mp4File -notmatch '\.mp4$') { $mp4File = "$mp4File.mp4" }
if (-not (Test-Path -LiteralPath $mp4File)) { throw ("Source mp4 not found: {0}" -f $mp4File) }

# LEFT
$mp4PoolL = "D:\images_for_slide_show\MP4s-epilogue\left\joyuu"
$overlayL = Get-ChildItem -LiteralPath $mp4PoolL -File -Filter *.mp4 | Get-Random
if (-not $overlayL) { throw ("No *.mp4 in {0}" -f $mp4PoolL) }

if (Test-Path -LiteralPath ".\overlay3-topleft.ps1") {
  .\overlay3-topleft.ps1 $mp4File $overlayL.FullName
} else {
  Write-Warning "skip: overlay3-topleft.ps1 not found."
}

# RIGHT
$mp4PoolR = "D:\images_for_slide_show\MP4s-joyuu\right"
$overlayR = Get-ChildItem -LiteralPath $mp4PoolR -File -Filter *.mp4 | Get-Random
if (-not $overlayR) { throw ("No *.mp4 in {0}" -f $mp4PoolR) }

if (Test-Path -LiteralPath ".\overlay3-topright.ps1") {
  .\overlay3-topright.ps1 $mp4File $overlayR.FullName
} else {
  Write-Warning "skip: overlay3-topright.ps1 not found."
}

# =========================
# 7) BGM 追加（無音対策）
# =========================
if (Test-Path -LiteralPath ".\add-bgm-epilogue.ps1") {
  .\add-bgm-epilogue.ps1 $mp4File
} else {
  Write-Warning "skip: add-bgm-epilogue.ps1 not found."
}

# =========================
# 8) アップロード
# =========================
Write-Host ("? python .\uploader10-joyuu.py {0}" -f $mp4File)
if (Test-Path -LiteralPath ".\uploader10-joyuu.py") {
  python .\uploader10-joyuu.py $mp4File
} else {
  Write-Warning "skip: uploader10-joyuu.py not found."
}

# =========================
# 9) OneDrive\today の同名テキストを done へ移動
# =========================
$oneDriveToday = "C:\Users\user\OneDrive\＊【エコビズ】\today"
$oneDriveDone  = Join-Path $oneDriveToday "done"
Ensure-Dir $oneDriveDone

$origTxt = Join-Path $oneDriveToday ($origBase + ".txt")
if (Test-Path -LiteralPath $origTxt) {
  $dest = Join-Path $oneDriveDone ([IO.Path]::GetFileName($origTxt))
  Move-Item -LiteralPath $origTxt -Destination $dest -Force
  Write-Host ("? Moved to done: {0}" -f $dest)
} else {
  Write-Warning ("? {0}.txt not found in today." -f $origBase)
}

# =========================
# 10) 後片付け（任意）
# =========================
Remove-Item *.mp4 -Force -ErrorAction SilentlyContinue
