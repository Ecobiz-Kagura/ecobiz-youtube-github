$ErrorActionPreference = "Stop"

# ============================================================
# 設定
# ============================================================

$OutputFormat = "srt"

# ============================================================
# 最新のMP4ファイルを1つ取得
# ============================================================

$latestVideo = Get-ChildItem `
    -LiteralPath (Get-Location).Path `
    -File `
    -Filter "*.mp4" `
    -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

# ============================================================
# ファイルが見つからない場合
# ============================================================

if (-not $latestVideo) {
    Write-Host ""
    Write-Host "MP4動画ファイルが見つかりません。"
    Write-Host "検索先: $((Get-Location).Path)"
    exit 1
}

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
Write-Host "フルパス     : $($latestVideo.FullName)"
Write-Host ""
Write-Host "[Whisper設定]"
Write-Host "言語         : Japanese"
Write-Host "モデル       : medium"
Write-Host "FP16         : False"
Write-Host "出力形式     : $OutputFormat"
Write-Host "出力先       : $($latestVideo.DirectoryName)"
Write-Host ""

# ============================================================
# 出力予定ファイル
# ============================================================

$outputFile = Join-Path `
    $latestVideo.DirectoryName `
    ($latestVideo.BaseName + "." + $OutputFormat)

Write-Host "[出力予定]"
Write-Host "ファイル     : $outputFile"
Write-Host ""

# ============================================================
# 実行確認
# デフォルトは Y
# ============================================================

$answer = Read-Host "この設定で文字起こししますか？ [Y/n]"

if ($answer -ne "" -and $answer -notmatch "^[Yy]$") {
    Write-Host ""
    Write-Host "処理をキャンセルしました。"
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

python -m whisper "$($latestVideo.FullName)" `
    --language Japanese `
    --model medium `
    --fp16 False `
    --output_format $OutputFormat `
    --output_dir "$($latestVideo.DirectoryName)"

# ============================================================
# 実行結果
# ============================================================

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "============================================================"
    Write-Host "文字起こしに失敗しました"
    Write-Host "============================================================"
    Write-Host "終了コード: $LASTEXITCODE"
    exit $LASTEXITCODE
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

if (Test-Path -LiteralPath $outputFile) {

    $outputInfo = Get-Item -LiteralPath $outputFile

    Write-Host "ファイルサイズ: $([math]::Round($outputInfo.Length / 1KB, 2)) KB"
    Write-Host "更新日時     : $($outputInfo.LastWriteTime)"
}
else {
    Write-Host ""
    Write-Host "注意: 出力ファイルを確認できませんでした。"
}

Write-Host ""