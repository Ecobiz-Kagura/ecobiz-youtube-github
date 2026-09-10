param(
    [Parameter(
        Position = 0,
        Mandatory = $false,
        HelpMessage = "文字起こしするMP4またはMOVファイルを指定してください。"
    )]
    [string]$InputVideo
)

$ErrorActionPreference = "Stop"

# ============================================================
# 設定
# ============================================================

$OutputFormat = "srt"
$WhisperLanguage = "Japanese"
$WhisperModel = "medium"
$UseFp16 = "False"

$SupportedExtensions = @(
    ".mp4",
    ".mov"
)

# ============================================================
# 対象動画ファイルを取得
#
# 引数あり:
#   指定されたMP4またはMOVファイルを使用
#
# 引数なし:
#   カレントディレクトリにある最新の
#   MP4またはMOVファイルを使用
# ============================================================

if ([string]::IsNullOrWhiteSpace($InputVideo)) {

    Write-Host ""
    Write-Host "入力ファイルが指定されていません。"
    Write-Host "カレントディレクトリから最新の動画を検索します。"
    Write-Host ""

    $latestVideo = Get-ChildItem `
        -LiteralPath (Get-Location).Path `
        -File `
        -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Extension.ToLower() -in $SupportedExtensions
        } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $latestVideo) {
        Write-Host "============================================================"
        Write-Host "MP4またはMOVファイルが見つかりません"
        Write-Host "============================================================"
        Write-Host "検索先: $((Get-Location).Path)"
        Write-Host ""
        exit 1
    }
}
else {

    # 環境変数を含むパスに対応
    $InputVideo = [Environment]::ExpandEnvironmentVariables($InputVideo)

    if (-not (Test-Path -LiteralPath $InputVideo -PathType Leaf)) {
        Write-Host ""
        Write-Host "============================================================"
        Write-Host "指定されたファイルが見つかりません"
        Write-Host "============================================================"
        Write-Host "指定内容: $InputVideo"
        Write-Host ""
        exit 1
    }

    $latestVideo = Get-Item -LiteralPath $InputVideo

    if ($latestVideo.Extension.ToLower() -notin $SupportedExtensions) {
        Write-Host ""
        Write-Host "============================================================"
        Write-Host "指定されたファイルはMP4またはMOVではありません"
        Write-Host "============================================================"
        Write-Host "指定内容: $($latestVideo.FullName)"
        Write-Host ""
        exit 1
    }
}

# ============================================================
# 出力予定ファイル
# ============================================================

$outputFile = Join-Path `
    $latestVideo.DirectoryName `
    ($latestVideo.BaseName + "." + $OutputFormat)

# ============================================================
# Whisperコマンドの表示用文字列
# ============================================================

$commandText = @(
    "python -m whisper"
    "`"$($latestVideo.FullName)`""
    "--language $WhisperLanguage"
    "--model $WhisperModel"
    "--fp16 $UseFp16"
    "--output_format $OutputFormat"
    "--output_dir `"$($latestVideo.DirectoryName)`""
) -join " "

# ============================================================
# 処理対象・設定を表示
# ============================================================

Write-Host ""
Write-Host "============================================================"
Write-Host "Whisper 文字起こし"
Write-Host "============================================================"
Write-Host ""
Write-Host "[入力動画]"
Write-Host "更新日時     : $($latestVideo.LastWriteTime)"
Write-Host "ファイル名   : $($latestVideo.Name)"
Write-Host "拡張子       : $($latestVideo.Extension)"
Write-Host "フルパス     : $($latestVideo.FullName)"
Write-Host ""
Write-Host "[Whisper設定]"
Write-Host "言語         : $WhisperLanguage"
Write-Host "モデル       : $WhisperModel"
Write-Host "FP16         : $UseFp16"
Write-Host "出力形式     : $OutputFormat"
Write-Host "出力先       : $($latestVideo.DirectoryName)"
Write-Host ""
Write-Host "[出力予定]"
Write-Host "ファイル     : $outputFile"
Write-Host ""
Write-Host "[実行コマンド]"
Write-Host $commandText
Write-Host ""

# ============================================================
# 実行確認
# デフォルトはY
# ============================================================

$answer = Read-Host "この設定で文字起こししますか？ [Y/n]"

if ($answer -ne "" -and $answer -notmatch "^[Yy]$") {
    Write-Host ""
    Write-Host "処理をキャンセルしました。"
    Write-Host ""
    exit 0
}

# ============================================================
# Whisperを実行
# ============================================================

Write-Host ""
Write-Host "============================================================"
Write-Host "文字起こし開始"
Write-Host "============================================================"
Write-Host ""
Write-Host "文字起こし中: $($latestVideo.Name)"
Write-Host "出力形式    : $OutputFormat"
Write-Host ""

try {
    python -m whisper "$($latestVideo.FullName)" `
        --language $WhisperLanguage `
        --model $WhisperModel `
        --fp16 $UseFp16 `
        --output_format $OutputFormat `
        --output_dir "$($latestVideo.DirectoryName)"

    $whisperExitCode = $LASTEXITCODE
}
catch {
    Write-Host ""
    Write-Host "============================================================"
    Write-Host "Whisperを実行できませんでした"
    Write-Host "============================================================"
    Write-Host "エラー内容: $($_.Exception.Message)"
    Write-Host ""
    exit 1
}

# ============================================================
# 実行結果
# ============================================================

if ($whisperExitCode -ne 0) {
    Write-Host ""
    Write-Host "============================================================"
    Write-Host "文字起こしに失敗しました"
    Write-Host "============================================================"
    Write-Host "終了コード: $whisperExitCode"
    Write-Host ""
    exit $whisperExitCode
}

# ============================================================
# 出力ファイル確認
# ============================================================

Write-Host ""
Write-Host "============================================================"
Write-Host "文字起こしが完了しました"
Write-Host "============================================================"
Write-Host "入力動画     : $($latestVideo.FullName)"
Write-Host "出力形式     : $OutputFormat"
Write-Host "出力ファイル : $outputFile"

if (Test-Path -LiteralPath $outputFile -PathType Leaf) {

    $outputInfo = Get-Item -LiteralPath $outputFile

    Write-Host "ファイルサイズ: $([math]::Round($outputInfo.Length / 1KB, 2)) KB"
    Write-Host "更新日時     : $($outputInfo.LastWriteTime)"
}
else {
    Write-Host ""
    Write-Host "注意: 出力ファイルを確認できませんでした。"
    Write-Host "Whisperの画面出力を確認してください。"
}

Write-Host ""