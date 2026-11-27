# ============================================================
# interview-make-short.ps1
# ============================================================

# ============================================================
# 設定
# ============================================================

$TargetDir = (Get-Location).Path

$SubVideoName = "programmer-kunou_3x.mp4"

$SubVideo = Join-Path $TargetDir $SubVideoName

$Width = 1080
$Height = 1920
$HalfHeight = 960

$FPS = 30

# 日本語判定用正規表現
# ASCII文字だけで記述するため文字化けしない

$JapanesePattern = '[\u3040-\u309F\u30A0-\u30FF\u3400-\u4DBF\u4E00-\u9FFF\uFF66-\uFF9F]'


# ============================================================
# FFmpeg / FFprobe の確認
# ============================================================

foreach ($Command in @("ffmpeg", "ffprobe")) {

    if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) {

        Write-Host ""
        Write-Host "$Command が見つかりません。" -ForegroundColor Red

        exit 1
    }
}


# ============================================================
# 合成用動画の確認
# ============================================================

if (-not (Test-Path -LiteralPath $SubVideo -PathType Leaf)) {

    Write-Host ""
    Write-Host "合成用動画が見つかりません。" -ForegroundColor Red
    Write-Host $SubVideo

    exit 1
}


# ============================================================
# 日本語ファイル名のMP4を検索
# ============================================================

$Files = @(
    Get-ChildItem `
        -LiteralPath $TargetDir `
        -File `
        -Filter "*.mp4" |
        Where-Object {

            $_.Name -match $JapanesePattern -and

            $_.Name -ne $SubVideoName -and

            $_.BaseName -notmatch '-short$'

        } |
        Sort-Object Name
)


# ============================================================
# 対象ファイルの確認
# ============================================================

if ($Files.Count -eq 0) {

    Write-Host ""
    Write-Host "対象ファイルがありません。" -ForegroundColor Yellow
    Write-Host "検索先: $TargetDir"

    exit 1
}


# ============================================================
# ファイル一覧の表示
# ============================================================

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " 日本語ファイル名のMP4一覧" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host ""
Write-Host "対象ファイル数: $($Files.Count)"
Write-Host ""

for ($i = 0; $i -lt $Files.Count; $i++) {

    Write-Host (
        "[{0}] {1}" -f ($i + 1), $Files[$i].Name
    )
}

Write-Host ""
Write-Host "[0] 終了"
Write-Host ""


# ============================================================
# ファイル選択
# ============================================================

while ($true) {

    $Selection = Read-Host "動画番号を入力してください"

    $Number = 0

    if (-not [int]::TryParse($Selection, [ref]$Number)) {

        Write-Host "整数を入力してください。" -ForegroundColor Red

        continue
    }

    if ($Number -eq 0) {

        Write-Host "終了します。"

        exit 0
    }

    if ($Number -lt 1 -or $Number -gt $Files.Count) {

        Write-Host "無効な番号です。" -ForegroundColor Red

        continue
    }

    break
}

$MainVideo = $Files[$Number - 1]


# ============================================================
# 出力ファイル名
# ============================================================

$OutputFile = Join-Path $TargetDir (
    $MainVideo.BaseName + "-short.mp4"
)


# ============================================================
# 出力ファイルの重複確認
# ============================================================

if (Test-Path -LiteralPath $OutputFile) {

    Write-Host ""
    Write-Host "出力ファイルが既に存在します。" -ForegroundColor Yellow
    Write-Host $OutputFile

    exit 1
}


# ============================================================
# 元動画の再生時間を取得
# ============================================================

$Duration = & ffprobe `
    -v error `
    -show_entries format=duration `
    -of "default=noprint_wrappers=1:nokey=1" `
    "$($MainVideo.FullName)"

if ($LASTEXITCODE -ne 0 -or -not $Duration) {

    Write-Host ""
    Write-Host "元動画の再生時間を取得できません。" -ForegroundColor Red

    exit 1
}

$Duration = ([string]$Duration).Trim()

$DurationValue = 0.0

if (
    -not [double]::TryParse(
        $Duration,
        [System.Globalization.NumberStyles]::Float,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [ref]$DurationValue
    ) -or $DurationValue -le 0
) {

    Write-Host "再生時間が不正です。" -ForegroundColor Red

    exit 1
}


# ============================================================
# 合成フィルター
# ============================================================

$Filter = (
    "[0:v]" +
    "scale=${Width}:${HalfHeight}:" +
    "force_original_aspect_ratio=decrease," +
    "pad=${Width}:${HalfHeight}:" +
    "(ow-iw)/2:(oh-ih)/2:black," +
    "setsar=1,fps=${FPS},format=yuv420p[top];" +

    "[1:v]" +
    "scale=${Width}:${HalfHeight}:" +
    "force_original_aspect_ratio=decrease," +
    "pad=${Width}:${HalfHeight}:" +
    "(ow-iw)/2:(oh-ih)/2:black," +
    "setsar=1,fps=${FPS},format=yuv420p[bottom];" +

    "[top][bottom]vstack=inputs=2[out]"
)


# ============================================================
# 処理内容の表示
# ============================================================

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " ショート動画作成設定" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host ""
Write-Host "上段動画   : $($MainVideo.Name)"
Write-Host "下段動画   : $SubVideoName"
Write-Host "再生時間   : $Duration 秒"
Write-Host "解像度     : $Width x $Height"
Write-Host "FPS        : $FPS"
Write-Host "音声       : 上段動画のみ"
Write-Host "出力先     : $OutputFile"
Write-Host ""


# ============================================================
# FFmpeg実行引数
# ============================================================

$FFmpegArgs = @(

    "-hide_banner"

    "-n"

    "-i"
    $MainVideo.FullName

    "-stream_loop"
    "-1"

    "-i"
    $SubVideo

    "-filter_complex"
    $Filter

    "-map"
    "[out]"

    "-map"
    "0:a?"

    "-t"
    $Duration

    "-c:v"
    "libx264"

    "-preset"
    "fast"

    "-crf"
    "20"

    "-pix_fmt"
    "yuv420p"

    "-c:a"
    "aac"

    "-b:a"
    "192k"

    "-movflags"
    "+faststart"

    $OutputFile
)


# ============================================================
# FFmpegによる動画合成
# ============================================================

Write-Host "動画の合成を開始します。" -ForegroundColor Cyan
Write-Host ""

& ffmpeg @FFmpegArgs

$Result = $LASTEXITCODE


# ============================================================
# 結果確認
# ============================================================

if (
    $Result -eq 0 -and
    (Test-Path -LiteralPath $OutputFile -PathType Leaf)
) {

    $OutputInfo = Get-Item -LiteralPath $OutputFile

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host " ショート動画の作成完了" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green

    Write-Host ""
    Write-Host "ファイル名 : $($OutputInfo.Name)"
    Write-Host "保存先     : $($OutputInfo.FullName)"
    Write-Host (
        "サイズ     : {0:N2} MB" -f ($OutputInfo.Length / 1MB)
    )
    Write-Host ""

} else {

    Write-Host ""
    Write-Host "動画の合成に失敗しました。" -ForegroundColor Red
    Write-Host "終了コード: $Result"

    exit 1
}