# ==============================
# ANSI-safe slideshow + video inserts (robust for Japanese paths)
#
# ★完全版（original画像挿入・安全）:
#   - "original"(半角/全角) を含む画像を 先頭10秒 + 途中7秒 で散布
#   - ★original探索は「$imgDir 配下」に限定（他フォルダ混入を防ぐ）
#   - 探索は $rootDir 配下を再帰（imgDir候補探索）
#   - HEIC/HEIF は stage で PNG に変換して安定化
#   - 最終的に残るのは $finalOutPath のみ（失敗時も残さない）
#   - StrictMode-safe（配列潰れ回避、後始末徹底）
#
# ★確認の自動スキップ:
#   - 10秒以内に入力がなければ自動で 'y' 扱い（続行）
#   - -NoConfirm で確認自体を完全にスキップ（常に続行）
# ==============================

param(
    [Parameter()]
    [ValidateRange(1, 600)]
    [int]$InsertClipLen = 7,

    [Parameter()]
    [ValidateRange(1, 600)]
    [int]$ConfirmTimeoutSec = 10,

    [Parameter()]
    [switch]$NoConfirm
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- Parameters ---
$MinDurationSec   = 3
$MaxDurationSec   = 6

$VideoCount       = 1

$FirstInsertSec   = 6
$InsertMinSec     = 10
$InsertMaxSec     = 15

$Fps = 30

# --- “original” inserts ---
$SpecialHoldSecHead    = 10   # 先頭
$SpecialHoldSecMid     = 7    # 途中
$SpecialKeyword        = "original"
$SpecialKeywordZenkaku = "ｏｒｉｇｉｎａｌ"
$SpecialInsertMinSec   = 20
$SpecialInsertMaxSec   = 40
$SpecialInsertEnabled  = $true

# --- Settings ---
$rootDir    = "D:\images_for_slide_show"
$hintRegex  = "じょゆう-おかだまりこ"   # 合わない/文字化けするなら ""（画像最多を採用）

$ImageExts = @(
    ".png",".jpg",".jpeg",".webp",".bmp",".gif",".tif",".tiff",
    ".heic",".heif",".jfif"   # ★jfif追加
)

$finalOutPath = "D:\ecobiz-youtube-github\12-joyuu-okada-mariko.mp4"

$ScriptRoot  = Split-Path -Parent $MyInvocation.MyCommand.Path
$ffmpegPath  = Join-Path $ScriptRoot "ffmpeg.exe"
$ffprobePath = Join-Path $ScriptRoot "ffprobe.exe"

# --- Helpers ---
function Get-RandomDuration { Get-Random -Minimum $MinDurationSec -Maximum ($MaxDurationSec + 1) }

function Write-ListFileUtf8NoBom {
    param([string]$Path, [string[]]$Lines)
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($Path, $Lines, $utf8NoBom)
}

function Get-StagedExt {
    param([Parameter(Mandatory)][string]$SourceExt)
    $e = $SourceExt.ToLowerInvariant()
    if ($e -eq ".jpeg") { return ".jpg" }
    if ($e -eq ".heic" -or $e -eq ".heif") { return ".png" }
    # jfif は jpg 扱いで stage して安定化（ffmpeg/concat向け）
    if ($e -eq ".jfif") { return ".jpg" }
    return $e
}

function Stage-ImageAscii {
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestPath
    )

    $srcExt = [System.IO.Path]::GetExtension($SourcePath).ToLowerInvariant()
    $dstExt = [System.IO.Path]::GetExtension($DestPath).ToLowerInvariant()

    if (($srcExt -eq ".heic" -or $srcExt -eq ".heif") -and ($dstExt -eq ".png")) {
        if (-not (Test-Path -LiteralPath $ffmpegPath)) { throw "ffmpeg not found for heic convert: $ffmpegPath" }

        & $ffmpegPath -y -hide_banner -loglevel error `
            -i "$SourcePath" -frames:v 1 `
            -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" `
            "$DestPath"

        if (-not (Test-Path -LiteralPath $DestPath)) {
            throw "HEIC/HEIF convert failed: $SourcePath -> $DestPath"
        }
        return
    }

    # jfif は jpg に変換（hardlink/copyだと拡張子だけ変わるので ffmpeg が困る場合がある）
    if (($srcExt -eq ".jfif") -and ($dstExt -eq ".jpg")) {
        if (-not (Test-Path -LiteralPath $ffmpegPath)) { throw "ffmpeg not found for jfif convert: $ffmpegPath" }

        & $ffmpegPath -y -hide_banner -loglevel error `
            -i "$SourcePath" -frames:v 1 `
            -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" `
            "$DestPath"

        if (-not (Test-Path -LiteralPath $DestPath)) {
            throw "JFIF convert failed: $SourcePath -> $DestPath"
        }
        return
    }

    try { New-Item -ItemType HardLink -Path $DestPath -Target $SourcePath -Force | Out-Null }
    catch { Copy-Item -LiteralPath $SourcePath -Destination $DestPath -Force }
}

function Get-VideoDurationSec {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "ffprobe input not found: $Path" }

    $args = @("-v","error","-show_entries","format=duration","-of","default=nk=1:nw=1", $Path)
    $out = & $ffprobePath @args 2>$null
    if (-not $out) { throw "ffprobe failed: $Path" }

    $first = ($out | Select-Object -First 1).Trim()
    $vd = 0.0
    if (-not [double]::TryParse(
        $first,
        [System.Globalization.NumberStyles]::Float,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [ref]$vd
    )) { throw "ffprobe returned non-numeric duration: '$first' ($Path)" }

    return $vd
}

function New-TempTxtPath {
    $raw = [System.IO.Path]::GetTempFileName()
    $txt = [System.IO.Path]::ChangeExtension($raw, ".txt")
    Remove-Item -LiteralPath $raw -Force -ErrorAction SilentlyContinue
    $txt
}

function New-GuidName([string]$prefix, [string]$ext){
    return ("{0}_{1}{2}" -f $prefix, ([guid]::NewGuid().ToString("N")), $ext)
}

function Make-SpecialImageClip {
    param(
        [Parameter(Mandatory)][System.IO.FileInfo]$ImageFile,
        [Parameter(Mandatory)][int]$HoldSec,
        [Parameter(Mandatory)][int]$Fps,
        [Parameter(Mandatory)][string]$FfmpegPath,
        [Parameter(Mandatory)][ref]$TempStageDirsRef,
        [Parameter(Mandatory)][ref]$SegmentFilesRef
    )

    $ext = Get-StagedExt -SourceExt $ImageFile.Extension

    $stageDir = Join-Path "D:\" ("stage_special_{0}" -f ([guid]::NewGuid().ToString("N")))
    New-Item -ItemType Directory -Path $stageDir -Force | Out-Null
    $TempStageDirsRef.Value += $stageDir

    $staged = Join-Path $stageDir ("000001{0}" -f $ext)
    Stage-ImageAscii -SourcePath $ImageFile.FullName -DestPath $staged

    $outMp4 = Join-Path "D:\" (New-GuidName -prefix "special" -ext ".mp4")
    $SegmentFilesRef.Value += $outMp4

    & $FfmpegPath -y `
        -loop 1 -t $HoldSec -i "$staged" `
        -r $Fps -fps_mode cfr -vsync cfr `
        -vf "setsar=1,scale=trunc(iw/2)*2:trunc(ih/2)*2" `
        -c:v libx264 -pix_fmt yuv420p "$outMp4"

    if (-not (Test-Path -LiteralPath $outMp4)) { throw "special image clip failed: $outMp4" }
    return $outMp4
}

# ★パス境界付きの「配下」判定（混入防止の要）
function Test-IsUnderPath {
    param(
        [Parameter(Mandatory)][string]$ChildPath,
        [Parameter(Mandatory)][string]$ParentPath
    )
    $cp = [System.IO.Path]::GetFullPath($ChildPath)
    $pp = [System.IO.Path]::GetFullPath($ParentPath)

    if (-not $pp.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $pp += [System.IO.Path]::DirectorySeparatorChar
    }
    return $cp.StartsWith($pp, [System.StringComparison]::OrdinalIgnoreCase)
}

# ★10秒タイムアウト確認（未入力なら自動で続行）
function Confirm-YesWithTimeout {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][int]$TimeoutSec,
        [Parameter()][switch]$NoConfirm
    )

    if ($NoConfirm) {
        Write-Host "$Prompt  -> (NoConfirm) 自動続行"
        return $true
    }

    Write-Host ""
    Write-Host "$Prompt  (y/N)  ※${TimeoutSec}秒以内に未入力なら 'y' とみなします -> 自動続行"

    $answer = $null
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
        if ([Console]::KeyAvailable) {
            $k = [Console]::ReadKey($true)
            $answer = $k.KeyChar
            break
        }
        Start-Sleep -Milliseconds 100
    }

    $sw.Stop()

    if ($null -eq $answer) {
        Write-Host "（タイムアウト ${TimeoutSec} 秒）→ 自動的に 'y' 扱いで続行します。"
        $answer = 'y'
    } else {
        Write-Host "入力: $answer"
    }

    if ($answer -eq 'y' -or $answer -eq 'Y') { return $true }
    return $false
}

# Unicode "動画" without Japanese literal
$folderDouga = ([string][char]0x52D5 + [string][char]0x753B)

# --- Validate tools/root ---
if (-not (Test-Path -LiteralPath $ffmpegPath))  { throw "ffmpeg not found: $ffmpegPath" }
if (-not (Test-Path -LiteralPath $ffprobePath)) { throw "ffprobe not found: $ffprobePath" }
if (-not (Test-Path -LiteralPath $rootDir))     { throw "root not found: $rootDir" }

# --- Ensure output directory exists ---
$finalDir = Split-Path -Parent $finalOutPath
if (-not (Test-Path -LiteralPath $finalDir)) { New-Item -ItemType Directory -Path $finalDir -Force | Out-Null }

$finalTmpOut = Join-Path $finalDir ("tmp_build_{0}.mp4" -f ([guid]::NewGuid().ToString("N")))

# --- Find Image directory candidates (ALWAYS array) ---
$allDirs = Get-ChildItem -LiteralPath $rootDir -Directory -Recurse -ErrorAction SilentlyContinue
$filtered = if ([string]::IsNullOrWhiteSpace($hintRegex)) { $allDirs } else { $allDirs | Where-Object { $_.FullName -match $hintRegex } }

$candidates = @(
    $filtered | ForEach-Object {
        $imgCount = (
            Get-ChildItem -LiteralPath $_.FullName -File -ErrorAction SilentlyContinue |
            Where-Object { $ImageExts -contains $_.Extension.ToLowerInvariant() } |
            Measure-Object
        ).Count
        if ($imgCount -gt 0) { [pscustomobject]@{ Dir = $_.FullName; Img = $imgCount } }
    }
)
if (@($candidates).Count -eq 0) { throw "Image folder not found under root. root=$rootDir hint=$hintRegex" }

$candidates = $candidates | Sort-Object Img -Descending
$imgDir = $candidates[0].Dir

# --- Find video dir named "動画" under imgDir ---
$videoDir = Get-ChildItem -LiteralPath $imgDir -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq $folderDouga } |
            Select-Object -First 1 -ExpandProperty FullName
if (-not $videoDir) { throw "video folder not found: $imgDir\$folderDouga" }

# --- Load inputs (ALL images for slideshow) ---
$allImages = @(
    Get-ChildItem -LiteralPath $imgDir -File -ErrorAction SilentlyContinue |
    Where-Object { $ImageExts -contains $_.Extension.ToLowerInvariant() }
)
if (@($allImages).Count -eq 0) { throw "Images not found: $imgDir" }

# --- ★ Find “original” images under imgDir only (NOT root) ---
$kw1 = $SpecialKeyword.ToLowerInvariant()
$kw2 = $SpecialKeywordZenkaku

$specialImages = @(
    Get-ChildItem -LiteralPath $imgDir -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object {
        ($ImageExts -contains $_.Extension.ToLowerInvariant()) -and (
            $_.Name.ToLowerInvariant().Contains($kw1) -or
            $_.Name.Contains($kw2)
        )
    } |
    Where-Object { Test-IsUnderPath -ChildPath $_.FullName -ParentPath $imgDir }
)

$allVideos = @(
    Get-ChildItem -LiteralPath $videoDir -Filter "*.mp4" -File -ErrorAction SilentlyContinue
)
if (@($allVideos).Count -eq 0) { throw "MP4 not found: $videoDir" }

Write-Host "IMG:  $imgDir"
Write-Host "MP4:  $videoDir"
Write-Host "IMG count: $(@($allImages).Count)"
Write-Host "MP4 count: $(@($allVideos).Count)"
Write-Host "FPS: $Fps"
Write-Host "InsertClipLen: $InsertClipLen"
Write-Host "ConfirmTimeoutSec: $ConfirmTimeoutSec (NoConfirm=$NoConfirm)"
Write-Host "OriginalHoldSecHead: $SpecialHoldSecHead"
Write-Host "OriginalHoldSecMid : $SpecialHoldSecMid (enabled=$SpecialInsertEnabled)"
Write-Host "special scope: $imgDir"
Write-Host "original images found (scope): $(@($specialImages).Count)"
Write-Host "FINAL: $finalOutPath"

# --- Work in D:\ ---
$origLocation = (Get-Location).Path
Set-Location D:\

$segmentFiles   = @()
$clipFiles      = @()
$tempStageDirs  = @()
$tempConcatTxts = @()

$moveCompleted = $false

try {
    for ($v = 0; $v -lt $VideoCount; $v++) {

        $seed = [int]([DateTime]::UtcNow.Ticks % [int]::MaxValue)
        $rng  = [System.Random]::new($seed)

        # --- special配列を「この実行内で固定」して使い回す（散布が安定） ---
        $specialPool = @($specialImages)

        # 先頭用：固定ピック（あれば）
        $headPick = $null
        if ($SpecialInsertEnabled -and $specialPool.Count -gt 0) {
            # "original (1).jfif" があれば優先、なければ先頭を固定
            $prefer = $specialPool | Where-Object { $_.Name -ieq "original (1).jfif" } | Select-Object -First 1
            $headPick = if ($prefer) { $prefer } else { $specialPool[0] }
            Write-Host "HEAD fixed pick: $($headPick.FullName)"
        }

        # --- スライドショー画像は originalも含める（除外しない） ---
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

        $timeline = @()
        $totalImgSec = 0.0

        if ($SpecialInsertEnabled -and $headPick) {
            $timeline += [pscustomobject]@{ Tag="[HEAD original]"; Path=$headPick.FullName; Sec=$SpecialHoldSecHead }
            $totalImgSec += $SpecialHoldSecHead
        }

        # 途中に「specialを全件ちりばめる」：候補(HEAD除外)を順番に散布
        $midSpecials = @()
        if ($SpecialInsertEnabled -and $specialPool.Count -gt 0) {
            $midSpecials = @($specialPool | Where-Object { if ($headPick) { $_.FullName -ne $headPick.FullName } else { $true } })
        }

        $midIndex = 0
        $nextSpecialPoint = 0.0
        if ($midSpecials.Count -gt 0) {
            $gap0 = Get-Random -Minimum $SpecialInsertMinSec -Maximum ($SpecialInsertMaxSec + 1)
            $nextSpecialPoint = [double]$gap0
        }

        for ($i = 0; $i -lt @($segments).Length; $i++) {
            foreach ($pair in $segments[$i]) {
                $img = $pair[0]
                $sec = [int]$pair[1]
                $timeline += [pscustomobject]@{ Tag=""; Path=$img.FullName; Sec=$sec }
                $totalImgSec += $sec
            }

            # --- MID special挿入（全件散布：順番に入れる） ---
            if ($midSpecials.Count -gt 0 -and $midIndex -lt $midSpecials.Count) {
                if ($nextSpecialPoint -gt 0 -and $totalImgSec -ge $nextSpecialPoint) {
                    $pickMid = $midSpecials[$midIndex]
                    $midIndex++

                    $timeline += [pscustomobject]@{ Tag="[MID original]"; Path=$pickMid.FullName; Sec=$SpecialHoldSecMid }
                    $totalImgSec += $SpecialHoldSecMid

                    $gap = Get-Random -Minimum $SpecialInsertMinSec -Maximum ($SpecialInsertMaxSec + 1)
                    $nextSpecialPoint = $totalImgSec + [double]$gap
                }
            }
        }

        Write-Host ""
        Write-Host "=== 生成タイムライン（先頭original + 秒数つき）==="
        Write-Host ("総数: {0} 件（original含む） / 合計: {1} 秒（画像部分のみ）" -f @($timeline).Count, [int][Math]::Round($totalImgSec))
        for ($k=0; $k -lt @($timeline).Count; $k++){
            $t = $timeline[$k]
            if ([string]::IsNullOrWhiteSpace($t.Tag)) {
                Write-Host ("{0:D5}: {1}  ({2}s)" -f $k, $t.Path, $t.Sec)
            } else {
                Write-Host ("{0:D5}: {1} {2}  ({3}s)" -f $k, $t.Tag, $t.Path, $t.Sec)
            }
        }

        # ===== 10秒内未入力なら自動続行（または -NoConfirm で完全スキップ）=====
        $ok = Confirm-YesWithTimeout -Prompt "この順で生成しますか？" -TimeoutSec $ConfirmTimeoutSec -NoConfirm:$NoConfirm
        if (-not $ok) { throw "User aborted." }

        $segmentFiles   = @()
        $clipFiles      = @()
        $tempStageDirs  = @()
        $tempConcatTxts = @()

        $masterLines = @()

        # --- build: HEAD special clip ---
        if ($SpecialInsertEnabled -and $headPick) {
            $mp40 = Make-SpecialImageClip `
                -ImageFile $headPick -HoldSec $SpecialHoldSecHead -Fps $Fps -FfmpegPath $ffmpegPath `
                -TempStageDirsRef ([ref]$tempStageDirs) -SegmentFilesRef ([ref]$segmentFiles)
            $masterLines += "file '$mp40'"
        }

        # --- build segments + MID special clips + normal clips ---
        $outTime2 = 0.0
        $nextSpecialPoint2 = 0.0
        $midIndex2 = 0
        if ($midSpecials.Count -gt 0) {
            $gap0b = Get-Random -Minimum $SpecialInsertMinSec -Maximum ($SpecialInsertMaxSec + 1)
            $nextSpecialPoint2 = [double]$gap0b
        }

        for ($i = 0; $i -lt @($segments).Length; $i++) {

            $seg = $segments[$i]

            $stageDir = Join-Path "D:\" ("stage_mizube_{0}_{1}" -f $i, ([guid]::NewGuid().ToString("N")))
            New-Item -ItemType Directory -Path $stageDir -Force | Out-Null
            $tempStageDirs += $stageDir

            $segLines = @()
            $idx = 1
            $lastPath = $null
            $segTotal = 0.0

            foreach ($pair in $seg) {
                $img = $pair[0]
                $dur = [int]$pair[1]
                $segTotal += [double]$dur

                $ext = Get-StagedExt -SourceExt $img.Extension
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

            $segMp4 = ("D:\segment_{0}_{1}.mp4" -f $i, ([guid]::NewGuid().ToString("N")))
            $segmentFiles += $segMp4

            & $ffmpegPath -y -safe 0 -f concat -i "$segConcatTxt" `
                -r $Fps -fps_mode cfr -vsync cfr `
                -vf "setsar=1,scale=trunc(iw/2)*2:trunc(ih/2)*2" `
                -c:v libx264 -pix_fmt yuv420p "$segMp4"

            if (-not (Test-Path -LiteralPath $segMp4)) { throw "segment failed: $segMp4" }
            $masterLines += "file '$segMp4'"
            $outTime2 += $segTotal

            # --- MID special（全件散布：順番） ---
            if ($SpecialInsertEnabled -and $midSpecials.Count -gt 0 -and $midIndex2 -lt $midSpecials.Count) {
                if ($nextSpecialPoint2 -gt 0 -and $outTime2 -ge $nextSpecialPoint2) {
                    $pickMid2 = $midSpecials[$midIndex2]
                    $midIndex2++

                    $mp4s = Make-SpecialImageClip `
                        -ImageFile $pickMid2 -HoldSec $SpecialHoldSecMid -Fps $Fps -FfmpegPath $ffmpegPath `
                        -TempStageDirsRef ([ref]$tempStageDirs) -SegmentFilesRef ([ref]$segmentFiles)

                    $masterLines += "file '$mp4s'"
                    $outTime2 += [double]$SpecialHoldSecMid

                    $gapb = Get-Random -Minimum $SpecialInsertMinSec -Maximum ($SpecialInsertMaxSec + 1)
                    $nextSpecialPoint2 = $outTime2 + [double]$gapb
                }
            }

            # --- normal video clip insert (not after last segment) ---
            if ($i -lt (@($segments).Length - 1)) {
                $rndVideo = $allVideos | Get-Random
                $clipPath = ("D:\clip_{0}.mp4" -f ([guid]::NewGuid().ToString("N")))
                $clipFiles += $clipPath

                $vdur = Get-VideoDurationSec -Path $rndVideo.FullName
                $maxStart = [Math]::Max(0, [Math]::Floor($vdur - $InsertClipLen))
                $ss = if ($maxStart -le 0) { 0 } else { Get-Random -Minimum 0 -Maximum ($maxStart + 1) }

                & $ffmpegPath -y -i "$($rndVideo.FullName)" -ss $ss -t $InsertClipLen -an `
                    -r $Fps -fps_mode cfr -vsync cfr `
                    -vf "setsar=1,scale=trunc(iw/2)*2:trunc(ih/2)*2" `
                    -c:v libx264 -pix_fmt yuv420p "$clipPath"

                if (-not (Test-Path -LiteralPath $clipPath)) { throw "clip failed: $clipPath" }
                $masterLines += "file '$clipPath'"
                $outTime2 += [double]$InsertClipLen
            }
        }

        $finalConcatTxt = New-TempTxtPath
        $tempConcatTxts += $finalConcatTxt
        Write-ListFileUtf8NoBom -Path $finalConcatTxt -Lines $masterLines

        if (Test-Path -LiteralPath $finalTmpOut) { Remove-Item -LiteralPath $finalTmpOut -Force -ErrorAction SilentlyContinue }

        & $ffmpegPath -y -safe 0 -f concat -i "$finalConcatTxt" `
            -r $Fps -fps_mode cfr -vsync cfr `
            -vf "setsar=1,scale=trunc(iw/2)*2:trunc(ih/2)*2" `
            -c:v libx264 -pix_fmt yuv420p "$finalTmpOut"

        if (-not (Test-Path -LiteralPath $finalTmpOut)) { throw "final tmp output missing: $finalTmpOut" }
    }

    if (Test-Path -LiteralPath $finalOutPath) { Remove-Item -LiteralPath $finalOutPath -Force }
    Move-Item -LiteralPath $finalTmpOut -Destination $finalOutPath -Force
    $moveCompleted = $true

    Write-Host "Saved: $finalOutPath"
}
finally {
    if (-not $moveCompleted) {
        if ($finalTmpOut -and (Test-Path -LiteralPath $finalTmpOut)) { Remove-Item -LiteralPath $finalTmpOut -Force -ErrorAction SilentlyContinue }
        if ($finalOutPath -and (Test-Path -LiteralPath $finalOutPath)) { Remove-Item -LiteralPath $finalOutPath -Force -ErrorAction SilentlyContinue }
    } else {
        if ($finalTmpOut -and (Test-Path -LiteralPath $finalTmpOut)) { Remove-Item -LiteralPath $finalTmpOut -Force -ErrorAction SilentlyContinue }
    }

    foreach ($t in $tempConcatTxts) { if ($t -and (Test-Path -LiteralPath $t)) { Remove-Item -LiteralPath $t -Force -ErrorAction SilentlyContinue } }
    foreach ($s in $segmentFiles)   { if ($s -and (Test-Path -LiteralPath $s)) { Remove-Item -LiteralPath $s -Force -ErrorAction SilentlyContinue } }
    foreach ($c in $clipFiles)      { if ($c -and (Test-Path -LiteralPath $c)) { Remove-Item -LiteralPath $c -Force -ErrorAction SilentlyContinue } }
    foreach ($d in $tempStageDirs)  { if ($d -and (Test-Path -LiteralPath $d)) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue } }

    try { Set-Location $origLocation } catch { }
}
