# random_vertical_split_5.ps1
# カレントディレクトリの動画からランダムに40～70秒を5本作成
# 9:16縦画面 1080x1920
# 上下に同じ動画を1枚ずつ配置
# 音量補正あり

$ErrorActionPreference = "Stop"

# ===== 設定 =====
$ClipCount = 5
$MinSeconds = 60
$MaxSeconds = 90
$OutputDirName = "vertical_random_clips"

$Width = 1080
$Height = 1920
$HalfHeight = 960

# ===== ffmpeg / ffprobe 確認 =====
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    Write-Host "ffmpeg が見つかりません。"
    exit
}

if (-not (Get-Command ffprobe -ErrorAction SilentlyContinue)) {
    Write-Host "ffprobe が見つかりません。"
    exit
}

# ===== 対象動画を取得 =====
$input = Get-ChildItem -File | Where-Object {
    $_.Extension -match '^\.(mp4|mov|mkv|avi|webm|m4v)$'
} | Sort-Object LastWriteTime -Descending | Select-Object -First 1

if (-not $input) {
    Write-Host "動画ファイルが見つかりません。"
    exit
}

# ===== 出力フォルダ =====
$outDir = Join-Path (Get-Location) $OutputDirName

if (Test-Path $outDir) {
    Add-Type -AssemblyName Microsoft.VisualBasic
    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
        $outDir,
        'OnlyErrorDialogs',
        'SendToRecycleBin'
    )
}

New-Item -ItemType Directory -Path $outDir | Out-Null

# ===== 動画時間を取得 =====
$durationText = ffprobe -v error `
    -show_entries format=duration `
    -of default=noprint_wrappers=1:nokey=1 `
    "$($input.FullName)"

$duration = [double]$durationText

if ($duration -lt $MinSeconds) {
    Write-Host "動画が $MinSeconds 秒未満のため処理できません。"
    exit
}

Write-Host "入力動画: $($input.Name)"
Write-Host "動画時間: $([math]::Round($duration, 2)) 秒"
Write-Host "出力先: $outDir"

# ===== ランダム切り出し + 縦画面上下配置 =====
for ($i = 1; $i -le $ClipCount; $i++) {

    $clipLength = Get-Random -Minimum $MinSeconds -Maximum ($MaxSeconds + 1)

    if ($clipLength -gt $duration) {
        $clipLength = [int]$duration
    }

    $maxStart = [int]($duration - $clipLength)
    $start = Get-Random -Minimum 0 -Maximum ($maxStart + 1)

    $outName = "{0}_vertical_{1:D2}_{2}s_start{3}s.mp4" -f `
        $input.BaseName, $i, $clipLength, $start

    $outPath = Join-Path $outDir $outName

    Write-Host ""
    Write-Host "作成中: $outName"
    Write-Host "開始位置: $start 秒"
    Write-Host "長さ: $clipLength 秒"

    ffmpeg -y `
        -ss $start `
        -i "$($input.FullName)" `
        -t $clipLength `
        -filter_complex "
[0:v]split=2[topsrc][bottomsrc];
[topsrc]scale=${Width}:${HalfHeight}:force_original_aspect_ratio=decrease,pad=${Width}:${HalfHeight}:(ow-iw)/2:(oh-ih)/2[top];
[bottomsrc]scale=${Width}:${HalfHeight}:force_original_aspect_ratio=decrease,pad=${Width}:${HalfHeight}:(ow-iw)/2:(oh-ih)/2[bottom];
[top][bottom]vstack=inputs=2[v]
" `
        -map "[v]" `
        -map 0:a:0? `
        -c:v libx264 `
        -preset medium `
        -crf 18 `
        -pix_fmt yuv420p `
        -c:a aac `
        -b:a 192k `
        -af "loudnorm,volume=1.3" `
        -movflags +faststart `
        "$outPath"
}

Write-Host ""
Write-Host "完了しました。"
Write-Host "出力先: $outDir"