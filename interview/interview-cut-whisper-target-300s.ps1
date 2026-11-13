
param(
    [string]$InputFile
)

$ErrorActionPreference = "Stop"

# ============================================================
# 設定
# ============================================================

$scriptStartTime = Get-Date

$ClipCount = 20
$MinSeconds = 240
$MaxSeconds = 360

$OutputDirName = "vertical_random_clips"

$WhisperLanguage = "Japanese"
$WhisperModel = "medium"

$ConfirmTimeoutSeconds = 10

# ＊は全角文字
$textDestination = "C:\Users\user\OneDrive\＊【エコビズ】\【whisper】"

# ============================================================
# 時刻付きメッセージ
# ============================================================

function Write-ProgressMessage {
    param([string]$Message)

    $now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$now] $Message"
}

# ============================================================
# 経過時間の表示
# ============================================================

function Format-ElapsedTime {
    param([TimeSpan]$TimeSpan)

    $hours = [int][math]::Floor($TimeSpan.TotalHours)

    return ("{0:D2}時間 {1:D2}分 {2:D2}秒" -f `
        $hours, $TimeSpan.Minutes, $TimeSpan.Seconds)
}

# ============================================================
# Y/N確認（10秒後に既定値）
# ============================================================

function Read-YesNoWithTimeout {
    param(
        [string]$Message,
        [int]$TimeoutSeconds = 10,
        [string]$DefaultAnswer = "Y"
    )

    Write-Host ""
    Write-Host "$Message [Y/N]"
    Write-Host "$TimeoutSeconds 秒以内に入力がなければ $DefaultAnswer"
    Write-Host "Enterキーは不要です。"

    try {
        while ([Console]::KeyAvailable) {
            [Console]::ReadKey($true) | Out-Null
        }
    } catch {}

    for ($remaining = $TimeoutSeconds; $remaining -gt 0; $remaining--) {

        Write-Host "`r残り $remaining 秒: " -NoNewline

        $oneSecondLater = (Get-Date).AddSeconds(1)

        while ((Get-Date) -lt $oneSecondLater) {

            try {
                if ([Console]::KeyAvailable) {

                    $key = [Console]::ReadKey($true)
                    $answer = $key.KeyChar.ToString()

                    if ($answer -match '^[Yy]$') {
                        Write-Host "Y"
                        return "Y"
                    }

                    if ($answer -match '^[Nn]$') {
                        Write-Host "N"
                        return "N"
                    }
                }
            } catch {
                Write-Host ""
                Write-ProgressMessage "キー入力取得不可。既定値を使用します。"
                return $DefaultAnswer
            }

            Start-Sleep -Milliseconds 100
        }
    }

    Write-Host ""
    Write-ProgressMessage "時間切れ。$DefaultAnswer を選択しました。"

    return $DefaultAnswer
}

# ============================================================
# プログラム開始
# ============================================================

Write-Host ""
Write-Host "============================================================"

Write-ProgressMessage "プログラムを開始しました。"
Write-Host "開始時刻: $($scriptStartTime.ToString('yyyy-MM-dd HH:mm:ss'))"

Write-Host "============================================================"

# ============================================================
# カレントディレクトリ
# ============================================================

$currentDirectory = (Get-Location).Path
$currentDirectoryName = Split-Path -Leaf $currentDirectory

$archiveDestination = Join-Path `
    $textDestination `
    $currentDirectoryName

Write-Host ""
Write-Host "実行ディレクトリ: $currentDirectory"
Write-Host "Whisper保存先: $textDestination"
Write-Host "保存用コピー先: $archiveDestination"

# ============================================================
# 保存先フォルダ作成
# ============================================================

foreach ($dir in @($textDestination, $archiveDestination)) {

    if (-not (Test-Path -LiteralPath $dir)) {

        New-Item `
            -ItemType Directory `
            -Path $dir `
            -Force | Out-Null

        Write-ProgressMessage "フォルダを作成しました: $dir"
    }
}

# ============================================================
# Whisper直下の既存ファイル削除
# ============================================================

Write-Host ""
Write-Host "注意: Whisper直下のファイルを削除します。"
Write-Host "サブフォルダ内は削除しません。"

$deleteAnswer = Read-YesNoWithTimeout `
    -Message "既存ファイルを削除しますか？" `
    -TimeoutSeconds $ConfirmTimeoutSeconds `
    -DefaultAnswer "Y"

if ($deleteAnswer -eq "Y") {

    $existingFiles = @(
        Get-ChildItem `
            -LiteralPath $textDestination `
            -File
    )

    foreach ($file in $existingFiles) {
        Remove-Item -LiteralPath $file.FullName -Force
    }

    Write-ProgressMessage "$($existingFiles.Count)個の既存ファイルを削除しました。"

} else {

    Write-ProgressMessage "削除を中止したため終了します。"
    exit
}

# ============================================================
# 必要コマンド確認
# ============================================================

Write-ProgressMessage "ffmpeg、ffprobe、Python、Whisperを確認しています。"

foreach ($cmd in @("ffmpeg", "ffprobe", "python")) {

    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {

        throw "$cmd が見つかりません。"
    }
}

& python -c "import whisper" 2>$null

if ($LASTEXITCODE -ne 0) {

    throw "Whisperがインストールされていません。"
}

Write-ProgressMessage "必要なコマンドの確認が完了しました。"

# ============================================================
# 入力動画の選択
# ============================================================

if ($InputFile) {

    $resolvedInputFile = (
        Resolve-Path -LiteralPath $InputFile -ErrorAction Stop
    ).Path

    $inputVideo = Get-Item -LiteralPath $resolvedInputFile

    if ($inputVideo.Extension -notmatch '^\.(mp4|mov|mkv|avi|webm|m4v)$') {
        throw "対応していない動画形式です。"
    }

} else {

    $inputVideo = Get-ChildItem `
        -LiteralPath $currentDirectory `
        -File |
        Where-Object {
            $_.Extension -match '^\.(mp4|mov|mkv|avi|webm|m4v)$'
        } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

if (-not $inputVideo) {
    throw "入力動画が見つかりません。"
}

Write-ProgressMessage "入力動画: $($inputVideo.FullName)"

# ============================================================
# 出力フォルダ初期化
# ============================================================

$outDir = Join-Path $currentDirectory $OutputDirName

if (Test-Path -LiteralPath $outDir) {

    Add-Type -AssemblyName Microsoft.VisualBasic

    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
        $outDir,
        'OnlyErrorDialogs',
        'SendToRecycleBin'
    )

    Write-ProgressMessage "既存フォルダをごみ箱に移動しました。"
}

New-Item -ItemType Directory -Path $outDir | Out-Null

Write-ProgressMessage "出力フォルダ: $outDir"

# ============================================================
# 元動画の時間取得
# ============================================================

$durationText = & ffprobe `
    -v error `
    -show_entries format=duration `
    -of default=noprint_wrappers=1:nokey=1 `
    "$($inputVideo.FullName)"

if ($LASTEXITCODE -ne 0 -or -not $durationText) {
    throw "動画時間の取得に失敗しました。"
}

$duration = [double]::Parse(
    "$durationText",
    [System.Globalization.CultureInfo]::InvariantCulture
)

if ($duration -lt $MinSeconds) {
    throw "動画が240秒未満です。"
}

Write-Host ""
Write-Host "============================================================"
Write-Host "入力動画: $($inputVideo.Name)"
Write-Host "動画時間: $duration 秒"
Write-Host "作成本数: $ClipCount"
Write-Host "切り出し時間: $MinSeconds - $MaxSeconds 秒"
Write-Host "============================================================"

# ============================================================
# ランダム動画作成
# 縦型変換なし
# 元動画の解像度と縦横比を維持
# ============================================================

$videoCreationStartTime = Get-Date

for ($i = 1; $i -le $ClipCount; $i++) {

    $singleVideoStartTime = Get-Date

    # --------------------------------------------------------
    # ランダムな動画長
    # --------------------------------------------------------

    $clipLength = Get-Random `
        -Minimum $MinSeconds `
        -Maximum ($MaxSeconds + 1)

    if ($clipLength -gt $duration) {
        $clipLength = [int][math]::Floor($duration)
    }

    # --------------------------------------------------------
    # ランダムな開始位置
    # --------------------------------------------------------

    $maxStart = [int][math]::Floor($duration - $clipLength)

    if ($maxStart -gt 0) {

        $start = Get-Random `
            -Minimum 0 `
            -Maximum ($maxStart + 1)

    } else {
        $start = 0
    }

    # --------------------------------------------------------
    # ファイル名
    # --------------------------------------------------------

    $outName = "{0}_clip_{1:D2}_{2}s_start{3}s.mp4" -f `
        $inputVideo.BaseName,
        $i,
        $clipLength,
        $start

    $outPath = Join-Path $outDir $outName

    Write-Host ""
    Write-Host "------------------------------------------------------------"

    Write-ProgressMessage "動画 $i / $ClipCount の作成を開始します。"

    Write-Host "ファイル: $outName"
    Write-Host "開始位置: $start 秒"
    Write-Host "長さ: $clipLength 秒"

    # --------------------------------------------------------
    # FFmpeg
    # 縦型変換・上下複製を廃止
    # --------------------------------------------------------

    & ffmpeg `
        -y `
        -ss $start `
        -i "$($inputVideo.FullName)" `
        -t $clipLength `
        -map "0:v:0" `
        -map "0:a:0?" `
        -c:v libx264 `
        -preset medium `
        -crf 18 `
        -pix_fmt yuv420p `
        -c:a aac `
        -b:a 192k `
        -af "loudnorm,volume=1.3" `
        -movflags +faststart `
        "$outPath"

    if ($LASTEXITCODE -ne 0) {
        throw "動画の作成に失敗しました: $outName"
    }

    $singleVideoElapsed = (Get-Date) - $singleVideoStartTime

    Write-ProgressMessage "動画 $i / $ClipCount を作成しました。"

    Write-Host "処理時間: $(Format-ElapsedTime $singleVideoElapsed)"
}

$videoCreationElapsed = (Get-Date) - $videoCreationStartTime

Write-ProgressMessage "20本の動画作成が完了しました。"

Write-Host "動画作成合計時間: $(Format-ElapsedTime $videoCreationElapsed)"

# ============================================================
# 作成動画一覧
# ============================================================

$createdVideos = @(
    Get-ChildItem `
        -LiteralPath $outDir `
        -File `
        -Filter "*.mp4" |
        Sort-Object Name
)

if ($createdVideos.Count -eq 0) {
    throw "文字起こし対象動画がありません。"
}

# ============================================================
# Whisper文字起こし
# ============================================================

Write-ProgressMessage "Whisperによる文字起こしを開始します。"

$whisperStartTime = Get-Date
$whisperNumber = 0

foreach ($videoFile in $createdVideos) {

    $whisperNumber++

    $singleWhisperStartTime = Get-Date

    $videoPath = $videoFile.FullName

    $commandText = `
        'python -m whisper "{0}" --language {1} --model {2} --fp16 False --output_format txt --output_dir "{3}"' -f `
        $videoPath,
        $WhisperLanguage,
        $WhisperModel,
        $outDir

    Write-Host ""
    Write-Host "------------------------------------------------------------"

    Write-ProgressMessage "文字起こし $whisperNumber / $($createdVideos.Count)"

    Write-Host "対象動画: $($videoFile.Name)"
    Write-Host "実行コマンド:"
    Write-Host $commandText

    $whisperAnswer = Read-YesNoWithTimeout `
        -Message "Whisperを実行しますか？" `
        -TimeoutSeconds $ConfirmTimeoutSeconds `
        -DefaultAnswer "Y"

    if ($whisperAnswer -eq "Y") {

        Write-ProgressMessage "Whisper処理を開始します。"

        & python `
            -m whisper `
            "$videoPath" `
            --language $WhisperLanguage `
            --model $WhisperModel `
            --fp16 False `
            --output_format txt `
            --output_dir "$outDir"

        $singleWhisperElapsed = (Get-Date) - $singleWhisperStartTime

        if ($LASTEXITCODE -eq 0) {

            Write-ProgressMessage "文字起こし完了: $($videoFile.Name)"

            Write-Host "処理時間: $(Format-ElapsedTime $singleWhisperElapsed)"

        } else {

            Write-ProgressMessage "文字起こし失敗: $($videoFile.Name)"
        }

    } else {

        Write-ProgressMessage "文字起こしをスキップしました。"
    }
}

$whisperElapsed = (Get-Date) - $whisperStartTime

Write-ProgressMessage "Whisper処理が終了しました。"

Write-Host "Whisper合計時間: $(Format-ElapsedTime $whisperElapsed)"

# ============================================================
# 完成TXT取得
# ============================================================

$textFiles = @(
    Get-ChildItem `
        -LiteralPath $outDir `
        -File `
        -Filter "*.txt" |
        Sort-Object Name
)

# ============================================================
# TXTを2か所に保存
# ============================================================

Write-ProgressMessage "文字起こし結果を保存します。"

$saveNumber = 0

foreach ($textFile in $textFiles) {

    $saveNumber++

    # --------------------------------------------------------
    # アーカイブ用フォルダにコピー
    # --------------------------------------------------------

    $archiveFile = Join-Path `
        $archiveDestination `
        $textFile.Name

    Copy-Item `
        -LiteralPath $textFile.FullName `
        -Destination $archiveFile `
        -Force

    Write-ProgressMessage `
        "[$saveNumber / $($textFiles.Count)] アーカイブにコピー: $($textFile.Name)"

    # --------------------------------------------------------
    # Whisper直下へ移動
    # --------------------------------------------------------

    $destinationFile = Join-Path `
        $textDestination `
        $textFile.Name

    Move-Item `
        -LiteralPath $textFile.FullName `
        -Destination $destinationFile `
        -Force

    Write-ProgressMessage `
        "[$saveNumber / $($textFiles.Count)] Whisper直下に移動: $($textFile.Name)"
}

# ============================================================
# 終了時刻・処理時間
# ============================================================

$scriptEndTime = Get-Date
$totalElapsed = $scriptEndTime - $scriptStartTime

Write-Host ""
Write-Host "============================================================"

Write-ProgressMessage "すべての処理が完了しました。"

Write-Host "============================================================"

Write-Host "処理対象動画:"
Write-Host $inputVideo.FullName

Write-Host ""
Write-Host "動画出力先:"
Write-Host $outDir

Write-Host ""
Write-Host "TXT保存先:"
Write-Host $textDestination

Write-Host ""
Write-Host "アーカイブ先:"
Write-Host $archiveDestination

Write-Host ""
Write-Host "作成動画数: $($createdVideos.Count)"
Write-Host "作成テキスト数: $($textFiles.Count)"

Write-Host ""
Write-Host "------------------------------------------------------------"
Write-Host "時間情報"
Write-Host "------------------------------------------------------------"

Write-Host "開始時刻: $($scriptStartTime.ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Host "終了時刻: $($scriptEndTime.ToString('yyyy-MM-dd HH:mm:ss'))"

Write-Host "動画作成合計時間: $(Format-ElapsedTime $videoCreationElapsed)"
Write-Host "Whisper合計時間: $(Format-ElapsedTime $whisperElapsed)"
Write-Host "総処理時間: $(Format-ElapsedTime $totalElapsed)"

Write-Host "============================================================"
