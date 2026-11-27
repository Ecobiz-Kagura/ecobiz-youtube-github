# ============================================================
# interview-make-short.ps1
# ============================================================

# ============================================================
# 設定
# ============================================================

$TargetDir = (Get-Location).Path

# 合成用動画のコピー元
$SourceDir = "./"

$SubVideoName = "10-programmer-kunou.mp4"

$SourceVideo = Join-Path $SourceDir $SubVideoName

# 合成用動画のコピー先
$SubVideo = Join-Path $TargetDir $SubVideoName

# 出力動画の解像度
$Width  = 1080
$Height = 1920

# フレームレート
$FPS = 30

# 上段動画の最大高さ
$MainMaxHeight = 600

# 上段動画の中心位置
$MainCenterY = 300

# 中央動画の最大高さ
$SubMaxHeight = 720

# 中央動画の位置調整
#    0 : 画面中央
#  100 : 中央より100px下
# -100 : 中央より100px上

$SubOffsetY = 0

# 背景色
$BackgroundColor = "black"

# 出力ファイル名の接尾辞
$OutputSuffix = "-short-center"

# 日本語判定用正規表現
# Unicode指定により文字化けを防止

$JapanesePattern = '[\u3040-\u309F\u30A0-\u30FF\u3400-\u4DBF\u4E00-\u9FFF\uFF66-\uFF9F]'


# ============================================================
# 合成用動画をカレントディレクトリにコピー
# ============================================================


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

if ((Get-Item -LiteralPath $SubVideo).Length -eq 0) {

    Write-Host "合成用動画が空のファイルです。" -ForegroundColor Red

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

            $_.BaseName -notmatch '-short(-center)?$'

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
    Write-Host ("    作成日時: {0:yyyy/MM/dd HH:mm:ss}" -f $Files[$i].CreationTime)
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
    $MainVideo.BaseName + $OutputSuffix + ".mp4"
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
# 中央動画の位置計算
# ============================================================

$SubCenterY = [int](($Height / 2) + $SubOffsetY)


# ============================================================
# 動画の配置チェック
# ============================================================

$MainTop    = $MainCenterY - ($MainMaxHeight / 2)
$MainBottom = $MainCenterY + ($MainMaxHeight / 2)

$SubTop     = $SubCenterY - ($SubMaxHeight / 2)
$SubBottom  = $SubCenterY + ($SubMaxHeight / 2)

if ($MainTop -lt 0 -or $MainBottom -gt $Height) {

    Write-Host "上段動画が画面からはみ出しています。" -ForegroundColor Red

    exit 1
}

if ($SubTop -lt 0 -or $SubBottom -gt $Height) {

    Write-Host "中央動画が画面からはみ出しています。" -ForegroundColor Red

    exit 1
}

if ($MainBottom -gt $SubTop -and $MainTop -lt $SubBottom) {

    Write-Host "注意: 動画の配置範囲が重なっています。" -ForegroundColor Yellow
}


# ============================================================
# 合成フィルター
# ============================================================

$Filter = (

    # 黒い背景を生成

    "color=c=${BackgroundColor}:" +
    "s=${Width}x${Height}:" +
    "r=${FPS}:" +
    "d=${Duration}[base];" +

    # 上段動画のサイズ調整

    "[0:v]" +
    "setpts=PTS-STARTPTS," +
    "scale=${Width}:${MainMaxHeight}:" +
    "force_original_aspect_ratio=decrease:" +
    "force_divisible_by=2," +
    "setsar=1," +
    "fps=${FPS}," +
    "format=yuv420p[main];" +

    # 中央動画のサイズ調整

    "[1:v]" +
    "setpts=PTS-STARTPTS," +
    "scale=${Width}:${SubMaxHeight}:" +
    "force_original_aspect_ratio=decrease:" +
    "force_divisible_by=2," +
    "setsar=1," +
    "fps=${FPS}," +
    "format=yuv420p[sub];" +

    # 上段動画を配置

    "[base][main]overlay=" +
    "x=(W-w)/2:" +
    "y=${MainCenterY}-h/2[tmp];" +

    # programmer-kunouを画面中央に配置

    "[tmp][sub]overlay=" +
    "x=(W-w)/2:" +
    "y=${SubCenterY}-h/2[out]"
)


# ============================================================
# 処理内容の表示
# ============================================================

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " ショート動画作成設定" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host ""
Write-Host "上段動画       : $($MainVideo.Name)"
Write-Host "中央動画       : $SubVideoName"
Write-Host "中央動画パス   : $SubVideo"
Write-Host "再生時間       : $Duration 秒"
Write-Host "解像度         : $Width x $Height"
Write-Host "FPS            : $FPS"
Write-Host "上段中心位置   : Y=$MainCenterY"
Write-Host "中央動画位置   : Y=$SubCenterY"
Write-Host "上段最大高さ   : $MainMaxHeight px"
Write-Host "中央最大高さ   : $SubMaxHeight px"
Write-Host "背景色         : $BackgroundColor"
Write-Host "音声           : 上段動画のみ"
Write-Host "出力先         : $OutputFile"
Write-Host ""


# ============================================================
# FFmpeg実行引数
# ============================================================

$FFmpegArgs = @(

    "-hide_banner"

    # 上書き禁止

    "-n"

    # 上段動画

    "-i"
    $MainVideo.FullName

    # 中央動画を無限に繰り返す

    "-stream_loop"
    "-1"

    "-i"
    $SubVideo

    # 合成フィルター

    "-filter_complex"
    $Filter

    # 合成した映像を使用

    "-map"
    "[out]"

    # 上段動画の音声のみ使用

    "-map"
    "0:a:0?"

    # 上段動画の長さに合わせる

    "-t"
    $Duration

    # 映像設定

    "-c:v"
    "libx264"

    "-preset"
    "fast"

    "-crf"
    "20"

    "-pix_fmt"
    "yuv420p"

    # 音声設定

    "-c:a"
    "aac"

    "-b:a"
    "192k"

    # Web再生の最適化

    "-movflags"
    "+faststart"

    # 出力ファイル

    $OutputFile
)


# ============================================================
# FFmpegによる動画合成
# ============================================================

# ============================================================
# 実行前のファイル情報表示と確認
# ============================================================

$MainInfo = Get-Item -LiteralPath $MainVideo.FullName -ErrorAction Stop
$SubInfo = Get-Item -LiteralPath $SubVideo -ErrorAction Stop

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " 動画合成の実行確認" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

foreach ($Info in @($MainInfo, $SubInfo)) {
    Write-Host ""
    if ($Info.FullName -eq $MainInfo.FullName) {
        Write-Host "上段動画"
    } else {
        Write-Host "中央動画"
    }
    Write-Host "  パス     : $($Info.FullName)"
    Write-Host ("  作成日時 : {0:yyyy/MM/dd HH:mm:ss}" -f $Info.CreationTime)
    Write-Host ("  更新日時 : {0:yyyy/MM/dd HH:mm:ss}" -f $Info.LastWriteTime)
}

Write-Host ""
Write-Host "出力先     : $OutputFile"
Write-Host "解像度     : $Width x $Height"
Write-Host "中央位置   : Y=$SubCenterY"
Write-Host ""

while ($true) {
    $Answer = (Read-Host "動画の合成を実行しますか？ [Y/n]").Trim()

    if ($Answer -eq "" -or $Answer -match '^y$') {
        break
    }

    if ($Answer -match '^n$') {
        Write-Host "動画の合成を中止しました。" -ForegroundColor Yellow
        exit 0
    }

    Write-Host "Y または N を入力してください。" -ForegroundColor Yellow
}

Write-Host ""
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

    Write-Host "中央位置   : Y=$SubCenterY"
    Write-Host ""

} else {

    Write-Host ""
    Write-Host "動画の合成に失敗しました。" -ForegroundColor Red
    Write-Host "終了コード: $Result"

    exit 1
}