# ==============================
# ANSI-safe slideshow + video inserts (robust for Japanese paths)
#  - 1st insert around t=$FirstInsertSec
#  - then every $InsertMinSec-$InsertMaxSec (random)
#  - each insert: $InsertClipLen sec from random mp4 (no audio, random start)
#  - PNG dir auto-detected by scanning D:\images_for_slide_show
#  - Video dir "動画" found without Japanese literal (Unicode code points)
#  - StrictMode-safe
#
# ★黒画面（たまに静止画/動画が真っ黒）対策を完全反映：
#   1) 最終 concat を -c copy しない（再エンコードしてPTSを正規化）
#   2) クリップ切り出しの -ss を input の後ろへ（GOP途中問題を回避）
#   3) 画像セグメント/クリップ生成でFPSを固定（フレーム欠落区間を作らない）
#   4) セグメント分割の「次回挿入点」を timeAfter 基準に修正（微ズレ防止）
#
# ★要件：
#   最終的に残るのは D:\ecobiz-youtube-github\11-takamine-hideko.mp4 のみ
#   （作業ファイルは最後に削除、失敗時も残さない）
# ==============================

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- Parameters ---
$MinDurationSec   = 3
$MaxDurationSec   = 6
$ImagesPerVideo   = 150
$VideoCount       = 1

$FirstInsertSec   = 6
$InsertMinSec     = 10
$InsertMaxSec     = 15
$InsertClipLen    = 7

# FPS固定
$Fps = 30

# --- Settings ---
$rootDir    = "D:\images_for_slide_show"
$hintRegex  = "じょゆう-たかみねひでこ"   # 合わない/文字化けするなら ""（png最多を採用）

# ★最終成果物（これだけ残す）
$finalOutPath = "D:\ecobiz-youtube-github\11-takamine-hideko.mp4"

# ffmpeg/ffprobe の場所：
# 1) このスクリプトと同じフォルダにある想定（推奨）
$ScriptRoot  = Split-Path -Parent $MyInvocation.MyCommand.Path
$ffmpegPath  = Join-Path $ScriptRoot "ffmpeg.exe"
$ffprobePath = Join-Path $ScriptRoot "ffprobe.exe"

# --- Helpers ---
function Get-RandomDuration {
    Get-Random -Minimum $MinDurationSec -Maximum ($MaxDurationSec + 1)
}

function Write-ListFileUtf8NoBom {
    param([string]$Path, [string[]]$Lines)
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($Path, $Lines, $utf8NoBom)
}

function Stage-ImageAscii {
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestPath
    )
    try { New-Item -ItemType HardLink -Path $DestPath -Target $SourcePath -Force | Out-Null }
    catch { Copy-Item -LiteralPath $SourcePath -Destination $DestPath -Force }
}

function Get-VideoDurationSec {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "ffprobe input not found: $Path"
    }
    $args = @(
        "-v","error",
        "-show_entries","format=duration",
        "-of","default=nk=1:nw=1",
        $Path
    )
    $out = & $ffprobePath @args 2>$null
    if (-not $out) { throw "ffprobe failed: $Path" }

    $first = ($out | Select-Object -First 1).Trim()

    $vd = 0.0
    if (-not [double]::TryParse(
        $first,
        [System.Globalization.NumberStyles]::Float,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [ref]$vd
    )) {
        throw "ffprobe returned non-numeric duration: '$first' ($Path)"
    }
    return $vd
}

function New-TempTxtPath {
    $raw = [System.IO.Path]::GetTempFileName()
    $txt = [System.IO.Path]::ChangeExtension($raw, ".txt")
    Remove-Item -LiteralPath $raw -Force -ErrorAction SilentlyContinue
    $txt
}

# Unicode "動画" without Japanese literal
$folderDouga = ([string][char]0x52D5 + [string][char]0x753B)

# --- Validate tools/root ---
if (-not (Test-Path -LiteralPath $ffmpegPath))  { throw "ffmpeg not found: $ffmpegPath" }
if (-not (Test-Path -LiteralPath $ffprobePath)) { throw "ffprobe not found: $ffprobePath" }
if (-not (Test-Path -LiteralPath $rootDir))     { throw "root not found: $rootDir" }

# --- Ensure output directory exists ---
$finalDir = Split-Path -Parent $finalOutPath
if (-not (Test-Path -LiteralPath $finalDir)) {
    New-Item -ItemType Directory -Path $finalDir -Force | Out-Null
}

# 生成は一旦テンポラリに出して、最後に Move で確定（失敗時に最終ファイルを残さない）
$finalTmpOut = Join-Path $finalDir ("tmp_build_{0}.mp4" -f (Get-Random))

# --- Find PNG directory candidates (ALWAYS array) ---
$allDirs = Get-ChildItem -LiteralPath $rootDir -Directory -Recurse -ErrorAction SilentlyContinue

if ([string]::IsNullOrWhiteSpace($hintRegex)) {
    $filtered = $allDirs
} else {
    $filtered = $allDirs | Where-Object { $_.FullName -match $hintRegex }
}

$candidates = @(
    $filtered | ForEach-Object {
        $pngCount = (
            Get-ChildItem -LiteralPath $_.FullName -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -match '^\.(png|PNG)$' } |
            Measure-Object
        ).Count
        if ($pngCount -gt 0) {
            [pscustomobject]@{ Dir = $_.FullName; Png = $pngCount }
        }
    }
)

if ($candidates.Count -eq 0) {
    throw "PNG folder not found under root. root=$rootDir hint=$hintRegex"
}

$candidates = $candidates | Sort-Object Png -Descending
$pngDir = $candidates[0].Dir

# --- Find video dir named "動画" under pngDir ---
$videoDir = Get-ChildItem -LiteralPath $pngDir -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq $folderDouga } |
            Select-Object -First 1 -ExpandProperty FullName

if (-not $videoDir) { throw "video folder not found: $pngDir\$folderDouga" }

# --- Load inputs ---
$allPng = @(
    Get-ChildItem -LiteralPath $pngDir -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -match '^\.(png|PNG)$' }
)
if ($allPng.Count -eq 0) { throw "PNG not found: $pngDir" }

$allVideos = @(
    Get-ChildItem -LiteralPath $videoDir -Filter "*.mp4" -File -ErrorAction SilentlyContinue
)
if ($allVideos.Count -eq 0) { throw "MP4 not found: $videoDir" }

$useCount = [Math]::Min($ImagesPerVideo, $allPng.Count)

Write-Host "PNG:  $pngDir"
Write-Host "MP4:  $videoDir"
Write-Host "PNG count: $($allPng.Count) / use: $useCount"
Write-Host "MP4 count: $($allVideos.Count)"
Write-Host "FPS: $Fps"
Write-Host "FINAL: $finalOutPath"

# --- Work in D:\ (作業用ファイル置き場) ---
Set-Location D:\

$segmentFiles   = @()
$clipFiles      = @()
$tempStageDirs  = @()
$tempConcatTxts = @()

try {
    for ($v = 0; $v -lt $VideoCount; $v++) {

        $randomFiles = $allPng | Get-Random -Count $useCount

        $currentTime     = 0
        $nextInsertPoint = $FirstInsertSec

        $segments = @()
        $currentSegment = @()

        foreach ($f in $randomFiles) {
            $dur = Get-RandomDuration

            # この1枚を含めた時刻を基準
            $timeAfter = $currentTime + $dur

            if (($currentSegment.Count -gt 0) -and ($timeAfter -ge $nextInsertPoint)) {
                $segments += ,@($currentSegment)
                $currentSegment = @()
                $interval = Get-Random -Minimum $InsertMinSec -Maximum ($InsertMaxSec + 1)
                $nextInsertPoint = $timeAfter + $interval
            }

            $currentSegment += ,@(@($f, $dur))
            $currentTime = $timeAfter
        }
        if ($currentSegment.Count -gt 0) { $segments += ,@($currentSegment) }

        Write-Host "Segments: $($segments.Count)"

        $finalConcatTxt = New-TempTxtPath
        $tempConcatTxts += $finalConcatTxt
        $masterLines = @()

        for ($i = 0; $i -lt $segments.Count; $i++) {

            $seg = $segments[$i]

            $stageDir = Join-Path "D:\" ("stage_mizube_{0}_{1}" -f $i, (Get-Random))
            New-Item -ItemType Directory -Path $stageDir -Force | Out-Null
            $tempStageDirs += $stageDir

            $segLines = @()
            $idx = 1
            foreach ($pair in $seg) {
                $img = $pair[0]
                $dur = $pair[1]
                $name = "{0:D6}.png" -f $idx
                $dst  = Join-Path $stageDir $name
                Stage-ImageAscii -SourcePath $img.FullName -DestPath $dst
                $segLines += "file '$dst'"
                $segLines += "duration $dur"
                $idx++
            }
            $lastName = "{0:D6}.png" -f ($idx - 1)
            $lastPath = Join-Path $stageDir $lastName
            $segLines += "file '$lastPath'"

            $segConcatTxt = New-TempTxtPath
            $tempConcatTxts += $segConcatTxt
            Write-ListFileUtf8NoBom -Path $segConcatTxt -Lines $segLines

            $segMp4 = ("D:\segment_{0}_{1}.mp4" -f $i, (Get-Random))
            $segmentFiles += $segMp4

            Write-Host "Segment #$i -> $segMp4"

            & $ffmpegPath -y -safe 0 -f concat -i "$segConcatTxt" `
                -r $Fps `
                -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" `
                -c:v libx264 -pix_fmt yuv420p "$segMp4"

            if (-not (Test-Path -LiteralPath $segMp4)) { throw "segment failed: $segMp4" }
            $masterLines += "file '$segMp4'"

            if ($i -lt $segments.Count - 1) {
                $rndVideo = $allVideos | Get-Random

                $clipPath = ("D:\clip_{0}.mp4" -f (Get-Random))
                $clipFiles += $clipPath

                $vdur = Get-VideoDurationSec -Path $rndVideo.FullName
                $maxStart = [Math]::Max(0, [Math]::Floor($vdur - $InsertClipLen))
                $ss = if ($maxStart -le 0) { 0 } else { Get-Random -Minimum 0 -Maximum ($maxStart + 1) }

                Write-Host "Clip -> $clipPath (ss=$ss) src=$($rndVideo.FullName)"

                & $ffmpegPath -y -i "$($rndVideo.FullName)" -ss $ss -t $InsertClipLen -an `
                    -r $Fps `
                    -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" `
                    -c:v libx264 -pix_fmt yuv420p "$clipPath"

                if (-not (Test-Path -LiteralPath $clipPath)) { throw "clip failed: $clipPath" }
                $masterLines += "file '$clipPath'"
            }
        }

        Write-ListFileUtf8NoBom -Path $finalConcatTxt -Lines $masterLines
        if (-not (Test-Path -LiteralPath $finalConcatTxt)) { throw "concat list missing: $finalConcatTxt" }

        Write-Host "Concat(re-encode) -> $finalTmpOut"

        if (Test-Path -LiteralPath $finalTmpOut) {
            Remove-Item -LiteralPath $finalTmpOut -Force -ErrorAction SilentlyContinue
        }

        & $ffmpegPath -y -safe 0 -f concat -i "$finalConcatTxt" `
            -r $Fps `
            -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" `
            -c:v libx264 -pix_fmt yuv420p "$finalTmpOut"

        if (-not (Test-Path -LiteralPath $finalTmpOut)) {
            throw "final tmp output missing: $finalTmpOut"
        }
    }

    # ★最終成果物だけ残す：既存を消してから Move（同一ドライブで原子的に置換）
    if (Test-Path -LiteralPath $finalOutPath) {
        Remove-Item -LiteralPath $finalOutPath -Force
    }
    Move-Item -LiteralPath $finalTmpOut -Destination $finalOutPath -Force

    Write-Host "Saved: $finalOutPath"
}
finally {
    # 最終成果物以外は残さない
    if ($finalTmpOut -and (Test-Path -LiteralPath $finalTmpOut)) {
        Remove-Item -LiteralPath $finalTmpOut -Force -ErrorAction SilentlyContinue
    }

    foreach ($t in $tempConcatTxts) { if ($t -and (Test-Path -LiteralPath $t)) { Remove-Item -LiteralPath $t -Force -ErrorAction SilentlyContinue } }
    foreach ($s in $segmentFiles)   { if ($s -and (Test-Path -LiteralPath $s)) { Remove-Item -LiteralPath $s -Force -ErrorAction SilentlyContinue } }
    foreach ($c in $clipFiles)      { if ($c -and (Test-Path -LiteralPath $c)) { Remove-Item -LiteralPath $c -Force -ErrorAction SilentlyContinue } }
    foreach ($d in $tempStageDirs)  { if ($d -and (Test-Path -LiteralPath $d)) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue } }
}


cd D:\ecobiz-youtube-github\