# ==============================
# ANSI-safe slideshow + video inserts (robust for Japanese paths)
#
# ★完全版（original画像挿入・安全・表示どおりに動く）：
#   - 先頭：original を「固定ピック」して $HeadOriginalHoldSec 秒
#   - 中間：original（先頭以外の全件）を必ず1回ずつ、均等に散布（取りこぼし無し）
#   - プレビューで「真のタイムライン（HEAD+MID+通常）」を秒数つきで表示 → y/N
#   - 探索は $rootDir 配下を再帰（original候補はrootDir再帰）
#   - HEIC/HEIF は stage で PNG 変換して安定化
#   - JFIF を選択対象に含める（.jfif を ImageExts に追加、ステージ拡張子 .jpg 扱い）
#   - originalが0件でも落ちない（specialを無効化して通常のみで続行）
#   - 最終的に残るのは $finalOutPath のみ（失敗時は残さない）
#   - StrictMode-safe（配列潰れ回避、後始末徹底）
# ==============================

param(
    [Parameter()]
    [ValidateRange(1, 600)]
    [int]$InsertClipLen = 7
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
$HeadOriginalHoldSec   = 10   # ★先頭originalは10秒
$MidOriginalHoldSec    = 7    # ★中間originalは7秒

$SpecialKeyword        = "original"
$SpecialKeywordZenkaku = "ｏｒｉｇｉｎａｌ"

# 先頭originalの固定ピック（優先）
$HeadOriginalPreferName = "original (1)"
$HeadPreferExtOrder = @(".jfif",".jpg",".jpeg",".png",".webp",".bmp",".gif",".tif",".tiff",".heic",".heif")

# --- Settings ---
$rootDir    = "D:\images_for_slide_show"
$hintRegex  = "じょゆう-にしなあきこ"   # 合わない/文字化けするなら ""（画像最多を採用）

$ImageExts = @(
    ".png",".jpg",".jpeg",".webp",".bmp",".gif",".tif",".tiff",
    ".heic",".heif",
    ".jfif"   # ★追加
)

$finalOutPath = "D:\ecobiz-youtube-github\12-joyuu-nisina-akiko.mp4"

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
    if ($e -eq ".jfif") { return ".jpg" }  # ★JFIFはjpg扱いで安定化
    if ($e -eq ".heic" -or $e -eq ".heif") { return ".png" }
    return $e
}

function Stage-ImageAscii {
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestPath
    )

    $srcExt = [System.IO.Path]::GetExtension($SourcePath).ToLowerInvariant()
    $dstExt = [System.IO.Path]::GetExtension($DestPath).ToLowerInvariant()

    # HEIC/HEIF -> PNG（ffmpeg変換）
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

    # それ以外（jfif含む）はハードリンク優先 → ダメならコピー
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

    Write-Host ("Insert [original] -> {0} (hold={1}s) src={2}" -f $outMp4, $HoldSec, $ImageFile.FullName)

    & $FfmpegPath -y `
        -loop 1 -t $HoldSec -i "$staged" `
        -r $Fps -fps_mode cfr -vsync cfr `
        -vf "setsar=1,scale=trunc(iw/2)*2:trunc(ih/2)*2" `
        -c:v libx264 -pix_fmt yuv420p "$outMp4"

    if (-not (Test-Path -LiteralPath $outMp4)) { throw "special image clip failed: $outMp4" }
    return $outMp4
}

function Pick-HeadOriginal {
    param(
        [Parameter(Mandatory)][System.IO.FileInfo[]]$SpecialImages,
        [Parameter(Mandatory)][string]$PreferName,
        [Parameter(Mandatory)][string[]]$PreferExtOrder
    )

    if (@($SpecialImages).Count -eq 0) { return $null }

    $cands = @($SpecialImages | Where-Object { $_.Name -like "*$PreferName*" })
    if (@($cands).Count -eq 0) { $cands = @($SpecialImages) }

    foreach ($ext in $PreferExtOrder) {
        $hit = $cands | Where-Object { $_.Extension.ToLowerInvariant() -eq $ext } | Select-Object -First 1
        if ($hit) { return $hit }
    }

    return ($cands | Sort-Object FullName | Select-Object -First 1)
}

function Confirm-Plan-Full {
    param(
        [Parameter()][System.IO.FileInfo]$HeadPick,
        [Parameter(Mandatory)][int]$HeadHoldSec,
        [Parameter(Mandatory)][object[]]$Segments,
        [Parameter(Mandatory)][hashtable]$SprinkleAfterSegment,
        [Parameter(Mandatory)][System.IO.FileInfo[]]$AllOriginals,
        [Parameter(Mandatory)][int]$OriginalHoldSecMid
    )

    Write-Host ""
    Write-Host "=== 生成タイムライン（先頭original + 秒数つき）==="

    $timeline = @()

    if ($HeadPick) {
        $timeline += [pscustomobject]@{ Path=$HeadPick.FullName; Dur=$HeadHoldSec; Tag="HEAD original" }
    }

    for ($si = 0; $si -lt @($Segments).Length; $si++) {
        foreach ($pair in $Segments[$si]) {
            $f = $pair[0]
            $d = [int]$pair[1]
            $timeline += [pscustomobject]@{ Path=$f.FullName; Dur=$d; Tag="" }
        }

        $afterIdx = $si + 1
        if ($SprinkleAfterSegment.ContainsKey($afterIdx)) {
            foreach ($pick in @($SprinkleAfterSegment[$afterIdx])) {
                $timeline += [pscustomobject]@{ Path=$pick.FullName; Dur=$OriginalHoldSecMid; Tag="MID original" }
            }
        }
    }

    $sum = 0.0
    foreach ($t in $timeline) { $sum += [double]$t.Dur }

    Write-Host ("総数: {0} 件（original含む） / 合計: {1} 秒（画像部分のみ）" -f @($timeline).Count, ([math]::Round($sum,1)))

    $i = 0
    foreach ($t in $timeline) {
        if ([string]::IsNullOrWhiteSpace($t.Tag)) {
            Write-Host ("{0:D5}: {1}  ({2}s)" -f $i, $t.Path, $t.Dur)
        } else {
            Write-Host ("{0:D5}: [{1}] {2}  ({3}s)" -f $i, $t.Tag, $t.Path, $t.Dur)
        }
        $i++
    }

    Write-Host ""
    Write-Host ("original候補数(root): {0}" -f @($AllOriginals).Count)
    if (@($AllOriginals).Count -gt 0) {
        Write-Host "original候補（全件）:"
        $AllOriginals | Sort-Object FullName | ForEach-Object { Write-Host "  - $($_.FullName)" }
    } else {
        Write-Host "original候補なし（special挿入は無効）"
    }

    Write-Host ""
    $ans = Read-Host "この画像順で生成しますか？ (y/N)"
    if ($ans -ne "y" -and $ans -ne "Y") { throw "User aborted." }
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
$allImagesRaw = @(
    Get-ChildItem -LiteralPath $imgDir -File -ErrorAction SilentlyContinue |
    Where-Object { $ImageExts -contains $_.Extension.ToLowerInvariant() }
)
if (@($allImagesRaw).Count -eq 0) { throw "Images not found: $imgDir" }

# --- Find “original” images under ROOT (include subfolders) ---
$kw1 = $SpecialKeyword.ToLowerInvariant()
$kw2 = $SpecialKeywordZenkaku

$specialImages = @(
    Get-ChildItem -LiteralPath $rootDir -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object {
        ($ImageExts -contains $_.Extension.ToLowerInvariant()) -and (
            $_.Name.ToLowerInvariant().Contains($kw1) -or
            $_.Name.Contains($kw2)
        )
    }
)

Write-Host "original images found (root): $(@($specialImages).Count)"
if (@($specialImages).Count -gt 0) {
    Write-Host "original candidates:"
    $specialImages | Sort-Object FullName | ForEach-Object { Write-Host "  - $($_.FullName)" }
}

# ★specialが0件なら、落とさずに通常のみで続行
$SpecialInsertEnabled = (@($specialImages).Count -gt 0)

# --- 通常スライド用：originalは除外（重複表示を避ける） ---
$specialSet = @{}
foreach ($s in @($specialImages)) { $specialSet[$s.FullName] = $true }

$allImages = @(
    $allImagesRaw | Where-Object { -not $specialSet.ContainsKey($_.FullName) }
)
if (@($allImages).Count -eq 0) {
    # もし全部originalだったら、除外せずに戻す（最低限動かす）
    $allImages = @($allImagesRaw)
}

$allVideos = @(
    Get-ChildItem -LiteralPath $videoDir -Filter "*.mp4" -File -ErrorAction SilentlyContinue
)
if (@($allVideos).Count -eq 0) { throw "MP4 not found: $videoDir" }

Write-Host "IMG:  $imgDir"
Write-Host "MP4:  $videoDir"
Write-Host "IMG count (non-original): $(@($allImages).Count)"
Write-Host "MP4 count: $(@($allVideos).Count)"
Write-Host "FPS: $Fps"
Write-Host "InsertClipLen: $InsertClipLen"
Write-Host ("OriginalHoldSecHead: {0}" -f $HeadOriginalHoldSec)
Write-Host ("OriginalHoldSecMid : {0} (enabled={1})" -f $MidOriginalHoldSec, $SpecialInsertEnabled)
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

        # ランダムなスライド順（通常画像のみ）
        $randomFiles = $allImages | Sort-Object { $rng.Next() }

        # --- Segments (for video clip inserts) ---
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

        # --- original HEAD pick (fixed/prefer) ---
        $headPick = $null
        if ($SpecialInsertEnabled) {
            $headPick = Pick-HeadOriginal -SpecialImages $specialImages -PreferName $HeadOriginalPreferName -PreferExtOrder $HeadPreferExtOrder
            Write-Host ("HEAD fixed pick: {0}" -f $headPick.FullName)
        }

        # --- MID original plan: all originals exactly once (except head) ---
        $midOriginalQueue = @()
        if ($SpecialInsertEnabled) {
            $rest = @($specialImages | Where-Object { $_.FullName -ne $headPick.FullName })
            $midOriginalQueue = $rest | Sort-Object { $rng.Next() }
        }

        # key:int -> FileInfo[]（同じ位置に複数入れられる）
        $sprinkleAfterSegment = @{}
        if (@($midOriginalQueue).Count -gt 0) {
            $segCount = @($segments).Length
            $slots = [Math]::Max(1, $segCount - 1)  # 最終セグメントの後には入れない

            for ($k = 0; $k -lt @($midOriginalQueue).Count; $k++) {
                $pos = [int][Math]::Round((($k + 1) * $slots) / (@($midOriginalQueue).Count + 1))
                if ($pos -lt 1) { $pos = 1 }
                if ($pos -gt $slots) { $pos = $slots }

                if (-not $sprinkleAfterSegment.ContainsKey($pos)) { $sprinkleAfterSegment[$pos] = @() }
                $sprinkleAfterSegment[$pos] += ,$midOriginalQueue[$k]
            }
        }

        # --- 漏れがあれば末尾寄せで追加（取りこぼしゼロ） ---
        if ($SpecialInsertEnabled) {
            $planned = @()
            if ($headPick) { $planned += $headPick.FullName }
            foreach ($v0 in $sprinkleAfterSegment.Values) {
                foreach ($x in @($v0)) { $planned += $x.FullName }
            }

            $plannedUnique = @($planned | Sort-Object -Unique)
            $specialUnique = @($specialImages.FullName | Sort-Object -Unique)

            $missing = @($specialUnique | Where-Object { $plannedUnique -notcontains $_ })
            if (@($missing).Count -gt 0) {
                Write-Host "WARNING: original散布の計画に漏れがあるため、末尾寄せで追加します:"
                $missing | ForEach-Object { Write-Host "  - $_" }

                $lastSlot = [Math]::Max(1, [Math]::Max(1, @($segments).Length - 1))
                if (-not $sprinkleAfterSegment.ContainsKey($lastSlot)) { $sprinkleAfterSegment[$lastSlot] = @() }

                foreach ($m in $missing) {
                    $fi = $specialImages | Where-Object { $_.FullName -eq $m } | Select-Object -First 1
                    if ($fi) { $sprinkleAfterSegment[$lastSlot] += ,$fi }
                }
            }
        }

        # --- プレビュー（真のタイムライン）→ y/N ---
        Confirm-Plan-Full `
            -HeadPick $headPick `
            -HeadHoldSec $HeadOriginalHoldSec `
            -Segments $segments `
            -SprinkleAfterSegment $sprinkleAfterSegment `
            -AllOriginals $specialImages `
            -OriginalHoldSecMid $MidOriginalHoldSec

        # --- build concat master list ---
        $finalConcatTxt = New-TempTxtPath
        $tempConcatTxts += $finalConcatTxt
        $masterLines = @()

        # --- head insert (original image) ---
        if ($SpecialInsertEnabled -and $headPick) {
            $mp40 = Make-SpecialImageClip `
                -ImageFile $headPick -HoldSec $HeadOriginalHoldSec -Fps $Fps -FfmpegPath $ffmpegPath `
                -TempStageDirsRef ([ref]$tempStageDirs) -SegmentFilesRef ([ref]$segmentFiles)

            $masterLines += "file '$mp40'"
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

            Write-Host "Segment #$i -> $segMp4 (sec=$segTotal)"

            & $ffmpegPath -y -safe 0 -f concat -i "$segConcatTxt" `
                -r $Fps -fps_mode cfr -vsync cfr `
                -vf "setsar=1,scale=trunc(iw/2)*2:trunc(ih/2)*2" `
                -c:v libx264 -pix_fmt yuv420p "$segMp4"

            if (-not (Test-Path -LiteralPath $segMp4)) { throw "segment failed: $segMp4" }
            $masterLines += "file '$segMp4'"

            # --- mid inserts: sprinkle ALL originals (possibly multiple per slot) ---
            if ($SpecialInsertEnabled) {
                $afterIdx = $i + 1
                if ($sprinkleAfterSegment.ContainsKey($afterIdx)) {
                    foreach ($pick in @($sprinkleAfterSegment[$afterIdx])) {
                        $mp4s = Make-SpecialImageClip `
                            -ImageFile $pick -HoldSec $MidOriginalHoldSec -Fps $Fps -FfmpegPath $ffmpegPath `
                            -TempStageDirsRef ([ref]$tempStageDirs) -SegmentFilesRef ([ref]$segmentFiles)

                        $masterLines += "file '$mp4s'"
                    }
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

                Write-Host "Clip -> $clipPath (ss=$ss) src=$($rndVideo.FullName)"

                & $ffmpegPath -y -i "$($rndVideo.FullName)" -ss $ss -t $InsertClipLen -an `
                    -r $Fps -fps_mode cfr -vsync cfr `
                    -vf "setsar=1,scale=trunc(iw/2)*2:trunc(ih/2)*2" `
                    -c:v libx264 -pix_fmt yuv420p "$clipPath"

                if (-not (Test-Path -LiteralPath $clipPath)) { throw "clip failed: $clipPath" }
                $masterLines += "file '$clipPath'"
            }
        }

        Write-ListFileUtf8NoBom -Path $finalConcatTxt -Lines $masterLines
        if (-not (Test-Path -LiteralPath $finalConcatTxt)) { throw "concat list missing: $finalConcatTxt" }

        Write-Host "Concat(re-encode) -> $finalTmpOut"
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
