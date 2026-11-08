param (
    [string]$InputFile
)

$ErrorActionPreference = "Stop"


# ============================================================
# 開始時刻
# ============================================================

$scriptStartTime = Get-Date


# ============================================================
# 設定
# ============================================================

$ClipCount = 20
$MinSeconds = 60
$MaxSeconds = 90

$OutputDirName = "vertical_random_clips"

$Width = 1080
$Height = 1920
$HalfHeight = 960

$WhisperLanguage = "Japanese"
$WhisperModel = "medium"

$ConfirmTimeoutSeconds = 10

# ＊は全角文字
$textDestination = "C:\Users\user\OneDrive\＊【エコビズ】\【whisper】"


# ============================================================
# 時刻付きメッセージ表示関数
# ============================================================

function Write-ProgressMessage {

    param (
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    Write-Host "[$now] $Message"
}


# ============================================================
# 経過時間を見やすく表示する関数
# ============================================================

function Format-ElapsedTime {

    param (
        [Parameter(Mandatory = $true)]
        [TimeSpan]$TimeSpan
    )

    $totalHours = [int][math]::Floor(
        $TimeSpan.TotalHours
    )

    return (
        "{0:D2}時間 {1:D2}分 {2:D2}秒" -f `
            $totalHours,
            $TimeSpan.Minutes,
            $TimeSpan.Seconds
    )
}


# ============================================================
# Y/N確認関数
# ============================================================

function Read-YesNoWithTimeout {

    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [int]$TimeoutSeconds = 10,

        [string]$DefaultAnswer = "Y"
    )

    Write-Host ""
    Write-Host "$Message [Y/N]"
    Write-Host "$TimeoutSeconds秒以内に入力がなければ、自動的に$DefaultAnswerを選択します。"
    Write-Host "YまたはNを押してください。Enterキーは不要です。"
    Write-Host ""

    try {

        while ([Console]::KeyAvailable) {

            [Console]::ReadKey($true) |
                Out-Null
        }

    } catch {
    }


    for (
        $remaining = $TimeoutSeconds;
        $remaining -gt 0;
        $remaining--
    ) {

        Write-Host `
            "`r残り $remaining 秒: " `
            -NoNewline

        $oneSecondLater = (Get-Date).AddSeconds(1)


        while ((Get-Date) -lt $oneSecondLater) {

            try {

                if ([Console]::KeyAvailable) {

                    $pressedKey = [Console]::ReadKey($true)

                    $answer = $pressedKey.KeyChar.ToString()


                    if ($answer -match '^[Yy]$') {

                        Write-Host "Y                    "

                        return "Y"
                    }


                    if ($answer -match '^[Nn]$') {

                        Write-Host "N                    "

                        return "N"
                    }
                }

            } catch {

                Write-Host ""

                Write-ProgressMessage `
                    "キー入力を取得できないため、自動的に$DefaultAnswerを選択します。"

                return $DefaultAnswer
            }


            Start-Sleep `
                -Milliseconds 100
        }
    }


    Write-Host `
        "`r時間切れのため、自動的に$DefaultAnswerを選択しました。                    "

    return $DefaultAnswer
}


# ============================================================
# プログラム開始
# ============================================================

Write-Host ""
Write-Host "============================================================"

Write-ProgressMessage `
    "プログラムを開始しました。"

Write-Host "開始時刻: $($scriptStartTime.ToString('yyyy-MM-dd HH:mm:ss'))"

Write-Host "============================================================"


# ============================================================
# 現在の実行ディレクトリ
# ============================================================

$currentDirectory = (Get-Location).Path

$currentDirectoryName = Split-Path `
    -Leaf `
    $currentDirectory


# ============================================================
# 実行ディレクトリ名と同じ名前の保存先
# ============================================================

$archiveDestination = Join-Path `
    $textDestination `
    $currentDirectoryName


Write-Host ""
Write-Host "実行ディレクトリ:"
Write-Host $currentDirectory

Write-Host ""
Write-Host "Whisper保存先:"
Write-Host $textDestination

Write-Host ""
Write-Host "保存用コピー先:"
Write-Host $archiveDestination


# ============================================================
# Whisper保存先作成
# ============================================================

if (-not (
    Test-Path `
        -LiteralPath $textDestination
)) {

    New-Item `
        -ItemType Directory `
        -Path $textDestination `
        -Force |
        Out-Null

    Write-ProgressMessage `
        "Whisper保存先フォルダを作成しました。"
}


# ============================================================
# 保存用サブフォルダ作成
# ============================================================

if (-not (
    Test-Path `
        -LiteralPath $archiveDestination
)) {

    New-Item `
        -ItemType Directory `
        -Path $archiveDestination `
        -Force |
        Out-Null

    Write-ProgressMessage `
        "保存用フォルダを作成しました: $archiveDestination"
}


# ============================================================
# Whisper直下の既存ファイル削除確認
# ============================================================

Write-Host ""
Write-Host "注意:"
Write-Host "【whisper】直下の既存ファイルだけを削除します。"
Write-Host "サブフォルダ内のファイルは削除しません。"


$deleteAnswer = Read-YesNoWithTimeout `
    -Message "Whisper保存先直下の既存ファイルをすべて削除しますか？" `
    -TimeoutSeconds $ConfirmTimeoutSeconds `
    -DefaultAnswer "Y"


if ($deleteAnswer -match '^[Yy]$') {

    $existingFiles = @(
        Get-ChildItem `
            -LiteralPath $textDestination `
            -File `
            -ErrorAction SilentlyContinue
    )


    if ($existingFiles.Count -gt 0) {

        $existingFiles |
            Remove-Item -Force

        Write-ProgressMessage `
            "$($existingFiles.Count)個の既存ファイルを削除しました。"

    } else {

        Write-ProgressMessage `
            "削除対象のファイルはありませんでした。"
    }

} else {

    Write-ProgressMessage `
        "削除を中止したため、プログラムを終了します。"

    exit
}


# ============================================================
# 必要コマンド確認
# ============================================================

Write-ProgressMessage `
    "ffmpeg、ffprobe、Python、Whisperを確認しています。"


if (-not (
    Get-Command `
        ffmpeg `
        -ErrorAction SilentlyContinue
)) {

    Write-ProgressMessage `
        "ffmpegが見つかりません。"

    exit
}


if (-not (
    Get-Command `
        ffprobe `
        -ErrorAction SilentlyContinue
)) {

    Write-ProgressMessage `
        "ffprobeが見つかりません。"

    exit
}


if (-not (
    Get-Command `
        python `
        -ErrorAction SilentlyContinue
)) {

    Write-ProgressMessage `
        "pythonが見つかりません。"

    exit
}


& python `
    -c `
    "import whisper" `
    2>$null


if ($LASTEXITCODE -ne 0) {

    Write-ProgressMessage `
        "現在のPython環境にWhisperがインストールされていません。"

    Write-Host ""
    Write-Host "次のコマンドでインストールしてください。"
    Write-Host "python -m pip install -U openai-whisper"

    exit
}


Write-ProgressMessage `
    "必要なコマンドの確認が完了しました。"


# ============================================================
# 処理対象動画を決定
# ============================================================

if ($InputFile) {

    try {

        $resolvedInputFile = `
            (Resolve-Path `
                -LiteralPath $InputFile `
                -ErrorAction Stop).Path

    } catch {

        Write-ProgressMessage `
            "指定されたファイルが見つかりません: $InputFile"

        exit
    }


    if (-not (
        Test-Path `
            -LiteralPath $resolvedInputFile `
            -PathType Leaf
    )) {

        Write-ProgressMessage `
            "指定されたパスはファイルではありません。"

        exit
    }


    $inputVideo = Get-Item `
        -LiteralPath $resolvedInputFile


    if (
        $inputVideo.Extension `
        -notmatch `
        '^\.(mp4|mov|mkv|avi|webm|m4v)$'
    ) {

        Write-ProgressMessage `
            "対応していない動画形式です: $($inputVideo.Extension)"

        Write-Host "対応形式: MP4 MOV MKV AVI WEBM M4V"

        exit
    }


    Write-ProgressMessage `
        "引数で指定された動画を使用します: $($inputVideo.FullName)"

} else {

    $inputVideo = Get-ChildItem `
        -LiteralPath $currentDirectory `
        -File |
        Where-Object {

            $_.Extension -match `
                '^\.(mp4|mov|mkv|avi|webm|m4v)$'

        } |
        Sort-Object `
            LastWriteTime `
            -Descending |
        Select-Object `
            -First 1


    if (-not $inputVideo) {

        Write-ProgressMessage `
            "動画ファイルが見つかりません。"

        exit
    }


    Write-ProgressMessage `
        "引数がないため最新動画を使用します: $($inputVideo.FullName)"
}


# ============================================================
# 出力フォルダ
# ============================================================

$outDir = Join-Path `
    $currentDirectory `
    $OutputDirName


if (
    Test-Path `
        -LiteralPath $outDir
) {

    Add-Type `
        -AssemblyName Microsoft.VisualBasic


    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
        $outDir,
        'OnlyErrorDialogs',
        'SendToRecycleBin'
    )


    Write-ProgressMessage `
        "既存の出力フォルダをごみ箱へ移動しました。"
}


New-Item `
    -ItemType Directory `
    -Path $outDir |
    Out-Null


Write-ProgressMessage `
    "動画出力フォルダを作成しました: $outDir"


# ============================================================
# 動画時間取得
# ============================================================

Write-ProgressMessage `
    "元動画の長さを取得しています。"


$durationText = & ffprobe `
    -v error `
    -show_entries format=duration `
    -of default=noprint_wrappers=1:nokey=1 `
    "$($inputVideo.FullName)"


if (
    $LASTEXITCODE -ne 0 `
    -or `
    -not $durationText
) {

    Write-ProgressMessage `
        "動画時間の取得に失敗しました。"

    exit
}


$duration = [double]$durationText


if ($duration -lt $MinSeconds) {

    Write-ProgressMessage `
        "動画が$MinSeconds秒未満のため処理できません。"

    exit
}


Write-ProgressMessage `
    "動画時間を取得しました: $([math]::Round($duration, 2))秒"


Write-Host ""
Write-Host "============================================================"
Write-Host "入力動画: $($inputVideo.Name)"
Write-Host "動画形式: $($inputVideo.Extension)"
Write-Host "動画時間: $([math]::Round($duration, 2))秒"
Write-Host "作成本数: $ClipCount"
Write-Host "切り出し時間: $MinSeconds - $MaxSeconds 秒"
Write-Host "============================================================"


# ============================================================
# ランダム動画作成
# ============================================================

Write-ProgressMessage `
    "$ClipCount 本の動画作成を開始します。"


$videoCreationStartTime = Get-Date


for (
    $i = 1;
    $i -le $ClipCount;
    $i++
) {

    $singleVideoStartTime = Get-Date


    $clipLength = Get-Random `
        -Minimum $MinSeconds `
        -Maximum ($MaxSeconds + 1)


    if ($clipLength -gt $duration) {

        $clipLength = `
            [int][math]::Floor($duration)
    }


    $maxStart = `
        [int][math]::Floor(
            $duration - $clipLength
        )


    if ($maxStart -gt 0) {

        $start = Get-Random `
            -Minimum 0 `
            -Maximum ($maxStart + 1)

    } else {

        $start = 0
    }


    $outName = `
        "{0}_vertical_{1:D2}_{2}s_start{3}s.mp4" -f `
        $inputVideo.BaseName,
        $i,
        $clipLength,
        $start


    $outPath = Join-Path `
        $outDir `
        $outName


    Write-Host ""
    Write-Host "------------------------------------------------------------"

    Write-ProgressMessage `
        "動画 $i / $ClipCount の作成を開始します。"

    Write-Host "ファイル: $outName"
    Write-Host "開始位置: $start 秒"
    Write-Host "長さ: $clipLength 秒"


    $videoFilter = @"
[0:v]split=2[topsrc][bottomsrc];
[topsrc]scale=${Width}:${HalfHeight}:force_original_aspect_ratio=decrease,pad=${Width}:${HalfHeight}:(ow-iw)/2:(oh-ih)/2[top];
[bottomsrc]scale=${Width}:${HalfHeight}:force_original_aspect_ratio=decrease,pad=${Width}:${HalfHeight}:(ow-iw)/2:(oh-ih)/2[bottom];
[top][bottom]vstack=inputs=2[v]
"@


    & ffmpeg `
        -y `
        -ss $start `
        -i "$($inputVideo.FullName)" `
        -t $clipLength `
        -filter_complex $videoFilter `
        -map "[v]" `
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

        Write-ProgressMessage `
            "動画の作成に失敗しました: $outName"

        exit
    }


    $singleVideoEndTime = Get-Date

    $singleVideoElapsed = `
        $singleVideoEndTime - $singleVideoStartTime


    Write-ProgressMessage `
        "動画 $i / $ClipCount を作成しました。"

    Write-Host "処理時間: $(Format-ElapsedTime $singleVideoElapsed)"
}


$videoCreationEndTime = Get-Date

$videoCreationElapsed = `
    $videoCreationEndTime - $videoCreationStartTime


Write-Host ""
Write-ProgressMessage `
    "全動画の作成が完了しました。"

Write-Host `
    "動画作成合計時間: $(Format-ElapsedTime $videoCreationElapsed)"


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

    Write-ProgressMessage `
        "文字起こし対象の動画がありません。"

    exit
}


# ============================================================
# Whisper文字起こし
# ============================================================

Write-Host ""
Write-Host "============================================================"

Write-ProgressMessage `
    "Whisperによる文字起こしを開始します。"

Write-Host "対象動画数: $($createdVideos.Count)"
Write-Host "============================================================"


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

    Write-ProgressMessage `
        "文字起こし $whisperNumber / $($createdVideos.Count) の準備をしています。"

    Write-Host ""
    Write-Host "対象動画:"
    Write-Host $videoFile.Name

    Write-Host ""
    Write-Host "実行予定のWhisperコマンド:"
    Write-Host $commandText


    $whisperAnswer = Read-YesNoWithTimeout `
        -Message "このWhisperコマンドを実行しますか？" `
        -TimeoutSeconds $ConfirmTimeoutSeconds `
        -DefaultAnswer "Y"


    if ($whisperAnswer -match '^[Yy]$') {

        Write-ProgressMessage `
            "文字起こし $whisperNumber / $($createdVideos.Count) を開始します。"


        & python `
            -m whisper `
            "$videoPath" `
            --language $WhisperLanguage `
            --model $WhisperModel `
            --fp16 False `
            --output_format txt `
            --output_dir "$outDir"


        $singleWhisperEndTime = Get-Date

        $singleWhisperElapsed = `
            $singleWhisperEndTime - $singleWhisperStartTime


        if ($LASTEXITCODE -eq 0) {

            Write-ProgressMessage `
                "文字起こしが完了しました: $($videoFile.Name)"

            Write-Host `
                "処理時間: $(Format-ElapsedTime $singleWhisperElapsed)"

        } else {

            Write-ProgressMessage `
                "文字起こしに失敗しました: $($videoFile.Name)"
        }

    } else {

        Write-ProgressMessage `
            "文字起こしをスキップしました: $($videoFile.Name)"
    }
}


$whisperEndTime = Get-Date

$whisperElapsed = `
    $whisperEndTime - $whisperStartTime


Write-Host ""

Write-ProgressMessage `
    "Whisper処理が終了しました。"

Write-Host `
    "Whisper合計時間: $(Format-ElapsedTime $whisperElapsed)"


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

Write-Host ""
Write-Host "============================================================"

Write-ProgressMessage `
    "文字起こし結果の保存を開始します。"

Write-Host "============================================================"


if ($textFiles.Count -gt 0) {

    $saveNumber = 0


    foreach ($textFile in $textFiles) {

        $saveNumber++


        # ----------------------------------------------------
        # 実行ディレクトリ名のサブフォルダへコピー
        # ----------------------------------------------------

        $archiveFile = Join-Path `
            $archiveDestination `
            $textFile.Name


        Copy-Item `
            -LiteralPath $textFile.FullName `
            -Destination $archiveFile `
            -Force


        Write-ProgressMessage `
            "[$saveNumber / $($textFiles.Count)] 保存用フォルダへコピーしました: $($textFile.Name)"


        # ----------------------------------------------------
        # Whisper直下へ移動
        # ----------------------------------------------------

        $destinationFile = Join-Path `
            $textDestination `
            $textFile.Name


        Move-Item `
            -LiteralPath $textFile.FullName `
            -Destination $destinationFile `
            -Force


        Write-ProgressMessage `
            "[$saveNumber / $($textFiles.Count)] Whisperフォルダへ移動しました: $($textFile.Name)"
    }

} else {

    Write-ProgressMessage `
        "保存対象のテキストファイルはありませんでした。"
}


# ============================================================
# 終了時刻・総処理時間
# ============================================================

$scriptEndTime = Get-Date

$totalElapsed = `
    $scriptEndTime - $scriptStartTime


Write-Host ""
Write-Host "============================================================"

Write-ProgressMessage `
    "すべての処理が完了しました。"

Write-Host "============================================================"

Write-Host ""
Write-Host "処理対象動画:"
Write-Host $inputVideo.FullName

Write-Host ""
Write-Host "動画の出力先:"
Write-Host $outDir

Write-Host ""
Write-Host "今回のテキスト保存先:"
Write-Host $textDestination

Write-Host ""
Write-Host "保存用コピー先:"
Write-Host $archiveDestination

Write-Host ""
Write-Host "作成動画数:"
Write-Host $createdVideos.Count

Write-Host ""
Write-Host "作成テキスト数:"
Write-Host $textFiles.Count


Write-Host ""
Write-Host "------------------------------------------------------------"
Write-Host "時間情報"
Write-Host "------------------------------------------------------------"

Write-Host ""
Write-Host "開始時刻:"
Write-Host $scriptStartTime.ToString("yyyy-MM-dd HH:mm:ss")

Write-Host ""
Write-Host "終了時刻:"
Write-Host $scriptEndTime.ToString("yyyy-MM-dd HH:mm:ss")

Write-Host ""
Write-Host "動画作成合計時間:"
Write-Host (
    Format-ElapsedTime `
        $videoCreationElapsed
)

Write-Host ""
Write-Host "Whisper合計時間:"
Write-Host (
    Format-ElapsedTime `
        $whisperElapsed
)

Write-Host ""
Write-Host "総処理時間:"
Write-Host (
    Format-ElapsedTime `
        $totalElapsed
)

Write-Host ""
Write-Host "============================================================"