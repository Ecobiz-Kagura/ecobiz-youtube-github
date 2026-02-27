param (
    [Parameter(Mandatory = $true)][string]$backgroundVideoPath,  # 背景動画
    [Parameter(Mandatory = $true)][string]$overlayVideoPath       # オーバーレイ動画
)

# === 1. 入力チェック ===
if (-not (Test-Path $backgroundVideoPath)) {
    Write-Host "? 背景動画 '$backgroundVideoPath' が見つかりません。"
    exit 1
}
if (-not (Test-Path $overlayVideoPath)) {
    Write-Host "? オーバーレイ動画 '$overlayVideoPath' が見つかりません。"
    exit 1
}
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    Write-Error "? ffmpeg が見つかりません。PATH を確認してください。"
    exit 1
}
if (-not (Get-Command ffprobe -ErrorAction SilentlyContinue)) {
    Write-Error "? ffprobe が見つかりません。PATH を確認してください。"
    exit 1
}

# === 2. 背景動画の長さ取得 ===
$durationCmd = "ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 `"$backgroundVideoPath`""
$duration = & cmd /c $durationCmd
$duration = [math]::Round([double]$duration, 2)

if (-not $duration -or $duration -le 0) {
    Write-Error "? 背景動画の長さが取得できませんでした。"
    exit 1
}

# === 3. 出力ファイル名（一時） ===
$tempOutput = [System.IO.Path]::Combine((Split-Path $backgroundVideoPath), "tmp-" + [System.IO.Path]::GetFileName($backgroundVideoPath))

# === 4. ffmpeg 実行：オーバーレイ動画をループ・フルHDにリサイズし中央合成 ===
$ffmpegArgs = @(
    "-y",
    "-i", "`"$backgroundVideoPath`"",
    "-stream_loop", "-1",
    "-i", "`"$overlayVideoPath`"",
    "-filter_complex", "[1:v]scale=1920:1080,format=yuva420p,colorchannelmixer=aa=0.5[ovl];[0:v][ovl]overlay=(main_w-overlay_w)/2:(main_h-overlay_h)/2",
    "-map", "0:a?",
    "-t", "$duration",
    "-c:v", "libx264",
    "-c:a", "aac",
    "`"$tempOutput`""
)
Start-Process -NoNewWindow -Wait -FilePath "ffmpeg" -ArgumentList $ffmpegArgs

# === 5. 上書き処理 ===
if (Test-Path $tempOutput) {
    try {
        Remove-Item -Path $backgroundVideoPath -Force
        Move-Item -Path $tempOutput -Destination $backgroundVideoPath
        Write-Host "? 完了: 背景動画にオーバーレイ（1920x1080）を重ねました。"
    } catch {
        Write-Error "? 上書き処理中にエラーが発生しました: $_"
    }
} else {
    Write-Error "? ffmpeg による出力が失敗しました。"
}
