# ==============================
# ANSI-safe slideshow + video inserts (robust for Japanese paths)
#  - 1st insert around t=$FirstInsertSec
#  - then every $InsertMinSec-$InsertMaxSec (random)
#  - each insert: $InsertClipLen sec from random mp4 (no audio, random start)
#  - Image dir auto-detected by scanning D:\images_for_slide_show (uses ALL image files, any ext)
#  - Video dir "動画" found without Japanese literal (Unicode code points)
#  - StrictMode-safe
#
# ★黒画面対策（完全反映）：
#   1) 最終 concat を -c copy しない（再エンコードしてPTSを正規化）
#   2) クリップ切り出しの -ss を input の後ろへ（GOP途中問題を回避）
#   3) 画像セグメント/クリップ生成でFPSを固定（フレーム欠落区間を作らない）
#   4) セグメント分割の「次回挿入点」を timeAfter 基準に修正（微ズレ防止）
#
# ★要件：
#   最終的に残るのは $finalOutPath のみ
#   （作業ファイルは最後に削除、失敗時も残さない）
#
# ★今回の修正（完全版）：
#   - 画像順を毎回確実にシャッフル（Randomインスタンスで Next()）
#   - StrictModeで落ちる「単一要素で配列が潰れる」問題を @() で常に回避
#   - 拡張子偽装を廃止（.jpg を .png としてリンクしない）→ 黒画面回避
#   - stage 側は 000001 + 元拡張子 で連番（ASCII化）し、concat の file 参照を正しく
# ==============================

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- Parameters ---
$MinDurationSec   = 3
$MaxDurationSec   = 6

$ImagesPerVideo   = 150   # 残してもOK（未使用）
$VideoCount       = 1

$FirstInsertSec   = 6
$InsertMinSec     = 10
$InsertMaxSec     = 15
$InsertClipLen    = 7

# FPS固定
$Fps = 30

# --- Settings ---
$rootDir    = "D:\images_for_slide_show"
$hintRegex  = "さっか-1970"   # 合わない/文字化けするなら ""（画像最多を採用）

# 対象画像拡張子（必要なら追加）
$ImageExts = @(".png",".jpg",".jpeg",".webp",".bmp",".gif",".tif",".tiff")

# ★最終成果物（これだけ残す）
$finalOutPath = "D:\ecobiz-youtube-github\11-sakka-1970.mp4"

# ffmpeg/ffprobe の場所（このスクリプトと同じフォルダ想定）
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

# --- Find Image directory candidates (ALWAYS array) ---
$allDirs = Get-ChildItem -LiteralPath $rootDir -Directory -Recurse -ErrorAction SilentlyContinue

if ([string]::IsNullOrWhiteSpace($hintRegex)) {
    $filtered = $allDirs
} else {
    $filtered = $allDirs | Where-Object { $_.FullName -match $hintRegex }
}

$candidates = @(
    $filtered | ForEach-Object {
        $imgCount = (
            Get-ChildItem -LiteralPath $_.FullName -File -ErrorAction SilentlyContinue |
            Where-Object { $ImageExts -contains $_.Extension.ToLowerInvariant() } |
            Measure-Object
        ).Count
        if ($imgCount -gt 0) {
            [pscustomobject]@{ Dir = $_.FullName; Img = $imgCount }
        }
    }
)

if (@($candidates).Count -eq 0) {
    throw "Image folder not found under root. root=$rootDir hint=$hintRegex"
}

$candidates = $candidates | Sort-Object Img -Descending
$imgDir = $candidates[0].Dir

# --- Find video dir named "動画" under imgDir ---
$videoDir = Get-ChildItem -LiteralPath $imgDir -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq $folderDouga } |
            Select-Object -First 1 -ExpandProperty FullName

if (-not $videoDir) { throw "video folder not found: $imgDir\$folderDouga" }

# --- Load inputs (ALL images) ---
$allImages = @(
    Get-ChildItem -LiteralPath $imgDir -File -ErrorAction SilentlyContinue |
    Where-Object { $ImageExts -contains $_.Extension.ToLowerInvariant() }
)
if (@($allImages).Count -eq 0) { throw "Images not found: $imgDir" }

$allVideos = @(
    Get-ChildItem -LiteralPath $videoDir -Filter "*.mp4" -File -ErrorAction SilentlyContinue
)
if (@($allVideos).Count -eq 0) { throw "MP4 not found: $videoDir" }

# ★全部使う
$useCount = @($allImages).Count

Write-Host "IMG:  $imgDir"
Write-Host "MP4:  $videoDir"
Write-Host "IMG count: $(@($allImages).Count) / use: $useCount"
Write-Host "MP4 count: $(@($allVideos).Count)"
Write-Host "FPS: $Fps"
Write-Host "FINAL: $finalOutPath"

# --- Work in D:\ (作業用ファイル置き場) ---
$origLocation = (Get-Location).Path
Set-Location D:\

$segmentFiles   = @()
$clipFiles      = @()
$tempStageDirs  = @()
$tempConcatTxts = @()

$moveCompleted = $false

try {
    for ($v = 0; $v -lt $VideoCount; $v++) {

        # ==========================
        # ★毎回必ず変わるシャッフル（Get-Random依存を減らす）
        # ==========================
        $seed = [int]([DateTime]::UtcNow.Ticks % [int]::MaxValue)
        $rng  = [System.Random]::new($seed)
        $randomFiles = $allImages | Sort-Object { $rng.Next() }

        $currentTime     = 0
        $nextInsertPoint = $FirstInsertSec

        $segments = @()
        $currentSegment = @()

        foreach ($f in $randomFiles) {
            $dur = Get-RandomDuration
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

        Write-Host "Segments: $(@($segments).Length)"

        $finalConcatTxt = New-TempTxtPath
        $tempConcatTxts += $finalConcatTxt
        $masterLines = @()

        # ★StrictMode安全：必ず配列化して Length を使う
        for ($i = 0; $i -lt @($segments).Length; $i++) {

            $seg = $segments[$i]

            $stageDir = Join-Path "D:\" ("stage_mizube_{0}_{1}" -f $i, (Get-Random))
            New-Item -ItemType Directory -Path $stageDir -Force | Out-Null
            $tempStageDirs += $stageDir

            $segLines = @()
            $idx = 1
            $lastPath = $null

            foreach ($pair in $seg) {
                $img = $pair[0]
                $dur = $pair[1]

                # ★拡張子偽装しない：元拡張子のまま連番（ASCII安全）
                $ext = $img.Extension.ToLowerInvariant()
                if ($ext -eq ".jpeg") { $ext = ".jpg" }

                $name = "{0:D6}{1}" -f $idx, $ext
                $dst  = Join-Path $stageDir $name
                Stage-ImageAscii -SourcePath $img.FullName -DestPath $dst

                $segLines += "file '$dst'"
                $segLines += "duration $dur"
                $lastPath = $dst
                $idx++
            }

            if (-not $lastPath) { throw "segment has no images (index=$i)" }
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

            if ($i -lt (@($segments).Length - 1)) {
                $rndVideo = $allVideos | Get-Random

                $clipPath = ("D:\clip_{0}.mp4" -f (Get-Random))
                $clipFiles += $clipPath

                $vdur = Get-VideoDurationSec -Path $rndVideo.FullName
                $maxStart = [Math]::Max(0, [Math]::Floor($vdur - $InsertClipLen))
                $ss = if ($maxStart -le 0) { 0 } else { Get-Random -Minimum 0 -Maximum ($maxStart + 1) }

                Write-Host "Clip -> $clipPath (ss=$ss) src=$($rndVideo.FullName)"

                # ★-ss を input の後ろへ（GOP途中対策）
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

    # ★最終成果物だけ残す：既存を消してから Move
    if (Test-Path -LiteralPath $finalOutPath) {
        Remove-Item -LiteralPath $finalOutPath -Force
    }
    Move-Item -LiteralPath $finalTmpOut -Destination $finalOutPath -Force
    $moveCompleted = $true

    Write-Host "Saved: $finalOutPath"

    try { Set-Location "D:\ecobiz-youtube-github\" } catch { }

}
finally {
    # 失敗時は成果物も残さない
    if (-not $moveCompleted) {
        if ($finalTmpOut -and (Test-Path -LiteralPath $finalTmpOut)) {
            Remove-Item -LiteralPath $finalTmpOut -Force -ErrorAction SilentlyContinue
        }
        if ($finalOutPath -and (Test-Path -LiteralPath $finalOutPath)) {
            Remove-Item -LiteralPath $finalOutPath -Force -ErrorAction SilentlyContinue
        }
    } else {
        if ($finalTmpOut -and (Test-Path -LiteralPath $finalTmpOut)) {
            Remove-Item -LiteralPath $finalTmpOut -Force -ErrorAction SilentlyContinue
        }
    }

    foreach ($t in $tempConcatTxts) { if ($t -and (Test-Path -LiteralPath $t)) { Remove-Item -LiteralPath $t -Force -ErrorAction SilentlyContinue } }
    foreach ($s in $segmentFiles)   { if ($s -and (Test-Path -LiteralPath $s)) { Remove-Item -LiteralPath $s -Force -ErrorAction SilentlyContinue } }
    foreach ($c in $clipFiles)      { if ($c -and (Test-Path -LiteralPath $c)) { Remove-Item -LiteralPath $c -Force -ErrorAction SilentlyContinue } }
    foreach ($d in $tempStageDirs)  { if ($d -and (Test-Path -LiteralPath $d)) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue } }

    try { Set-Location $origLocation } catch { }
}
