# random_vertical_split_5.ps1
#
# カレントディレクトリにある最新動画を対象にする
# ランダムな60～90秒の動画を20本作成する
# 9:16縦画面 1080x1920
# 同じ動画を上下に配置する
# 音量を補正する
# 作成した動画をWhisperで文字起こしする
#
# 完成したテキストは
#
# 1.
# C:\Users\user\OneDrive\＊【エコビズ】\【whisper】
#
# 2.
# C:\Users\user\OneDrive\＊【エコビズ】\【whisper】\
#     実行しているディレクトリと同じ名前のフォルダ
#
# の両方に保存する
#
# 例:
# D:\動画\赤塚 で実行した場合
#
# C:\Users\user\OneDrive\＊【エコビズ】\【whisper】\赤塚
#
# にもTXTを保存する
#
# 【whisper】直下の既存ファイルは開始時に削除する
# 実行ディレクトリ名の保存フォルダ内は削除しない
#
# Y/N確認では10秒以内に入力がない場合、自動的にYを選択する
# YまたはNの入力時にEnterキーは不要

$ErrorActionPreference = "Stop"


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


# ============================================================
# Whisper基本保存先
# ============================================================

# ＊は全角文字
$textDestination = "C:\Users\user\OneDrive\＊【エコビズ】\【whisper】"


# ============================================================
# 現在の実行ディレクトリを取得
# ============================================================

$currentDirectory = (Get-Location).Path

$currentDirectoryName = Split-Path `
    -Leaf `
    $currentDirectory


# ============================================================
# 実行ディレクトリと同じ名前の保存先
# ============================================================

$archiveDestination = Join-Path `
    $textDestination `
    $currentDirectoryName


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


    # 以前のキー入力が残っている場合は消去
    try {

        while ([Console]::KeyAvailable) {

            [Console]::ReadKey($true) |
                Out-Null
        }

    } catch {

        # キー入力状態を取得できない環境ではそのまま続行
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

                    $answer = `
                        $pressedKey.KeyChar.ToString()


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

                Write-Host `
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
# 保存先を表示
# ============================================================

Write-Host ""
Write-Host "============================================================"
Write-Host "実行ディレクトリ:"
Write-Host $currentDirectory

Write-Host ""
Write-Host "実行ディレクトリ名:"
Write-Host $currentDirectoryName

Write-Host ""
Write-Host "Whisperテキスト保存先:"
Write-Host $textDestination

Write-Host ""
Write-Host "保存用コピー先:"
Write-Host $archiveDestination

Write-Host "============================================================"


# ============================================================
# Whisper基本保存先を作成
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


    Write-Host ""
    Write-Host "Whisper保存先フォルダを作成しました:"
    Write-Host $textDestination
}


# ============================================================
# 実行ディレクトリ名の保存フォルダを作成
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


    Write-Host ""
    Write-Host "保存用フォルダを作成しました:"
    Write-Host $archiveDestination

} else {

    Write-Host ""
    Write-Host "保存用フォルダは既に存在します:"
    Write-Host $archiveDestination
}


# ============================================================
# Whisper保存先の削除確認
# ============================================================

Write-Host ""
Write-Host "注意:"
Write-Host "【whisper】直下の既存ファイルだけを削除します。"
Write-Host ""
Write-Host "次の保存用フォルダ内は削除しません:"
Write-Host $archiveDestination


$deleteAnswer = Read-YesNoWithTimeout `
    -Message "Whisper保存先直下の既存ファイルをすべて削除しますか？" `
    -TimeoutSeconds $ConfirmTimeoutSeconds `
    -DefaultAnswer "Y"


if ($deleteAnswer -match '^[Yy]$') {

    # -Fileだけなのでサブディレクトリは削除しない
    $existingFiles = @(
        Get-ChildItem `
            -LiteralPath $textDestination `
            -File `
            -ErrorAction SilentlyContinue
    )


    if ($existingFiles.Count -gt 0) {

        $existingFiles |
            Remove-Item `
                -Force


        Write-Host ""
        Write-Host "$($existingFiles.Count)個の既存ファイルを削除しました。"

    } else {

        Write-Host ""
        Write-Host "削除対象のファイルはありませんでした。"
    }

} else {

    Write-Host ""
    Write-Host "削除を中止したため、プログラムを終了します。"

    exit
}


# ============================================================
# ffmpeg確認
# ============================================================

if (-not (
    Get-Command `
        ffmpeg `
        -ErrorAction SilentlyContinue
)) {

    Write-Host ""
    Write-Host "ffmpegが見つかりません。"

    exit
}


# ============================================================
# ffprobe確認
# ============================================================

if (-not (
    Get-Command `
        ffprobe `
        -ErrorAction SilentlyContinue
)) {

    Write-Host ""
    Write-Host "ffprobeが見つかりません。"

    exit
}


# ============================================================
# Python確認
# ============================================================

if (-not (
    Get-Command `
        python `
        -ErrorAction SilentlyContinue
)) {

    Write-Host ""
    Write-Host "pythonが見つかりません。"

    exit
}


# ============================================================
# Whisper確認
# ============================================================

& python `
    -c `
    "import whisper" `
    2>$null


if ($LASTEXITCODE -ne 0) {

    Write-Host ""
    Write-Host "現在のPython環境にWhisperがインストールされていません。"

    Write-Host ""
    Write-Host "次のコマンドでインストールしてください。"

    Write-Host ""
    Write-Host "python -m pip install -U openai-whisper"

    exit
}


# ============================================================
# 対象動画を取得
# ============================================================

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

    Write-Host ""
    Write-Host "動画ファイルが見つかりません。"

    exit
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


    Write-Host ""
    Write-Host "既存の出力フォルダをごみ箱へ移動しました。"
}


New-Item `
    -ItemType Directory `
    -Path $outDir |
    Out-Null


# ============================================================
# 動画時間を取得
# ============================================================

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

    Write-Host ""
    Write-Host "動画時間の取得に失敗しました。"

    exit
}


$duration = [double]$durationText


if ($duration -lt $MinSeconds) {

    Write-Host ""
    Write-Host "動画が$MinSeconds秒未満のため処理できません。"

    exit
}


Write-Host ""
Write-Host "============================================================"
Write-Host "入力動画:"
Write-Host $inputVideo.Name

Write-Host ""
Write-Host "動画時間:"
Write-Host "$([math]::Round($duration, 2))秒"

Write-Host ""
Write-Host "動画出力先:"
Write-Host $outDir

Write-Host "============================================================"


# ============================================================
# ランダム切り出しと縦画面上下配置
# ============================================================

for (
    $i = 1;
    $i -le $ClipCount;
    $i++
) {

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
    Write-Host "動画 $i / $ClipCount"
    Write-Host "作成中:"
    Write-Host $outName

    Write-Host ""
    Write-Host "開始位置: $start秒"
    Write-Host "長さ: $clipLength秒"


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

        Write-Host ""
        Write-Host "動画の作成に失敗しました:"
        Write-Host $outName

        exit
    }


    Write-Host ""
    Write-Host "動画を作成しました:"
    Write-Host $outName
}


# ============================================================
# 作成動画の一覧を取得
# ============================================================

$createdVideos = @(
    Get-ChildItem `
        -LiteralPath $outDir `
        -File `
        -Filter "*.mp4" |
        Sort-Object Name
)


if ($createdVideos.Count -eq 0) {

    Write-Host ""
    Write-Host "文字起こし対象の動画がありません。"

    exit
}


# ============================================================
# Whisperによる文字起こし
# ============================================================

Write-Host ""
Write-Host "============================================================"
Write-Host "Whisperによる文字起こしを開始します。"
Write-Host "対象動画数: $($createdVideos.Count)"
Write-Host "============================================================"


$whisperNumber = 0


foreach ($videoFile in $createdVideos) {

    $whisperNumber++

    $videoPath = $videoFile.FullName


    $commandText = `
        'python -m whisper "{0}" --language {1} --model {2} --fp16 False --output_format txt --output_dir "{3}"' -f `
        $videoPath,
        $WhisperLanguage,
        $WhisperModel,
        $outDir


    Write-Host ""
    Write-Host "------------------------------------------------------------"
    Write-Host "文字起こし $whisperNumber / $($createdVideos.Count)"

    Write-Host ""
    Write-Host "対象動画:"
    Write-Host $videoFile.Name

    Write-Host ""
    Write-Host "実行予定のコマンド:"
    Write-Host $commandText


    $whisperAnswer = Read-YesNoWithTimeout `
        -Message "このコマンドを実行しますか？" `
        -TimeoutSeconds $ConfirmTimeoutSeconds `
        -DefaultAnswer "Y"


    if ($whisperAnswer -match '^[Yy]$') {

        Write-Host ""
        Write-Host "文字起こし中:"
        Write-Host $videoFile.Name


        & python `
            -m whisper `
            "$videoPath" `
            --language $WhisperLanguage `
            --model $WhisperModel `
            --fp16 False `
            --output_format txt `
            --output_dir "$outDir"


        if ($LASTEXITCODE -eq 0) {

            Write-Host ""
            Write-Host "文字起こしが完了しました:"
            Write-Host $videoFile.Name

        } else {

            Write-Host ""
            Write-Host "文字起こしに失敗しました:"
            Write-Host $videoFile.Name
        }

    } else {

        Write-Host ""
        Write-Host "文字起こしをスキップしました:"
        Write-Host $videoFile.Name
    }
}


# ============================================================
# 完成したテキストファイルを取得
# ============================================================

$textFiles = @(
    Get-ChildItem `
        -LiteralPath $outDir `
        -File `
        -Filter "*.txt" |
        Sort-Object Name
)


Write-Host ""
Write-Host "============================================================"
Write-Host "文字起こし結果を保存します。"
Write-Host "============================================================"


# ============================================================
# テキストを2か所へ保存
# ============================================================

if ($textFiles.Count -gt 0) {

    foreach ($textFile in $textFiles) {

        # ----------------------------------------------------
        # 実行ディレクトリ名のフォルダへコピー
        # ----------------------------------------------------

        $archiveFile = Join-Path `
            $archiveDestination `
            $textFile.Name


        Copy-Item `
            -LiteralPath $textFile.FullName `
            -Destination $archiveFile `
            -Force


        Write-Host ""
        Write-Host "保存用フォルダへコピーしました:"
        Write-Host $archiveFile


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


        Write-Host ""
        Write-Host "Whisperフォルダへ移動しました:"
        Write-Host $destinationFile
    }

} else {

    Write-Host ""
    Write-Host "保存対象のテキストファイルはありませんでした。"
}


# ============================================================
# 完了表示
# ============================================================

Write-Host ""
Write-Host "============================================================"
Write-Host "すべての処理が完了しました。"
Write-Host "============================================================"

Write-Host ""
Write-Host "入力動画:"
Write-Host $inputVideo.Name

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