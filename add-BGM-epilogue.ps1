param(
    [Parameter(Mandatory = $true)]
    [string]$InputMp4
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# BGMフォルダ
$BgmDir = "D:\images_for_slide_show\MP3s\epilogue"

# ffmpeg が見つかるか確認（PATH or フルパス想定）
$ffmpegCmd = Get-Command ffmpeg -ErrorAction SilentlyContinue
if (-not $ffmpegCmd) {
    throw "ffmpeg が見つかりません。PATH を確認してください。"
}

if (-not (Test-Path -LiteralPath $InputMp4)) {
    throw "入力MP4が見つかりません: $InputMp4"
}

# フォルダ内のMP3ファイルからランダムに1つ選択
$bgmFiles = Get-ChildItem -Path $BgmDir -Filter "*.mp3" -File -ErrorAction SilentlyContinue
if (-not $bgmFiles -or $bgmFiles.Count -eq 0) {
    throw "BGMファイルが見つかりません: $BgmDir"
}
$BgmPath = ($bgmFiles | Get-Random).FullName
    
Write-Host "選択されたBGM: $BgmPath"

# 出力ファイル名（元動画名に _bgm を追加）
$OutputMp4 = [System.IO.Path]::ChangeExtension($InputMp4, $null) + "_bgm.mp4"

# filter_complex
$filter = "[1:a]volume=0.3[bgm];[0:a]volume=1[v0];[v0][bgm]amix=inputs=2:duration=first:dropout_transition=2[aout]"

# ffmpeg 引数（配列で安全に渡す）
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

# 実行
& $ffmpegCmd.Source @args
