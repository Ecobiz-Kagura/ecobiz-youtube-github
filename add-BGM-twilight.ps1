param(
    [Parameter(Mandatory = $true)]
    [string]$InputMp4
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# =========================
# BGMフォルダ（silent）
# =========================
$BgmDir = "D:\images_for_slide_show\MP3s\twilight"

# =========================
# ffmpeg 確認
# =========================
$ffmpegCmd = Get-Command ffmpeg -ErrorAction SilentlyContinue
if (-not $ffmpegCmd) {
    throw "ffmpeg が見つかりません。PATH を確認してください。"
}

# =========================
# 入力MP4確認
# =========================
if (-not (Test-Path -LiteralPath $InputMp4)) {
    throw "入力MP4が見つかりません: $InputMp4"
}

# =========================
# BGMファイル取得（★必ず配列化）
# =========================
$bgmFiles = @(Get-ChildItem -Path $BgmDir -Filter "*.mp3" -File -ErrorAction SilentlyContinue)

if ($bgmFiles.Count -eq 0) {
    throw "BGMファイルが見つかりません: $BgmDir"
}

$BgmPath = ($bgmFiles | Get-Random).FullName
Write-Host "選択されたBGM: $BgmPath"

# =========================
# 出力ファイル名
# =========================
$OutputMp4 = [System.IO.Path]::ChangeExtension($InputMp4, $null) + "_bgm.mp4"

# =========================
# filter_complex
# =========================
$filter = @"
[0:a]aformat=channel_layouts=stereo,volume=1[v0];
[1:a]aformat=channel_layouts=stereo,volume=0.12[bgm];
[v0][bgm]amix=inputs=2:duration=first:dropout_transition=2[aout]
"@

# =========================
# ffmpeg 引数（配列）
# =========================
$args = @(
    "-hide_banner",
    "-i", $InputMp4,
    "-stream_loop", "-1",
    "-i", $BgmPath,
    "-filter_complex", $filter,
    "-map", "0:v:0",
    "-map", "[aout]",
    "-c:v", "copy",
    "-c:a", "aac",
    "-shortest",
    "-y",
    $OutputMp4
)

# =========================
# 実行
# =========================
& $ffmpegCmd.Source @args
