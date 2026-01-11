param(
    [Parameter(Mandatory = $true)]
    [string]$InputMp4
)

# BGMフォルダ
$BgmDir = "D:\ecobiz-youtube-uploader\google-trans\MP3s\twilight"

# フォルダ内のMP3ファイルからランダムに1つ選択
$BgmPath = Get-ChildItem -Path $BgmDir -Filter "*.mp3" | Get-Random | Select-Object -ExpandProperty FullName

if (-not $BgmPath) {
    throw "BGMファイルが見つかりません: $BgmDir"
}

Write-Host "選択されたBGM: $BgmPath"

# 出力ファイル名（元動画名に _bgm を追加）
$OutputMp4 = [System.IO.Path]::ChangeExtension($InputMp4, $null) + "_bgm.mp4"

# ffmpegコマンド
ffmpeg -hide_banner `
  -i "$InputMp4" `
  -stream_loop -1 -i "$BgmPath" `
  -filter_complex "[1:a]volume=0.3[bgm];[0:a]volume=1[v0];[v0][bgm]amix=inputs=2:duration=first:dropout_transition=2:normalize=1[aout]" `
  -map 0:v:0 -map "[aout]" `
  -c:v copy -c:a aac -shortest "$OutputMp4"

# 成功したら元ファイルに上書き
if (Test-Path "$OutputMp4") {
    Copy-Item -Force "$OutputMp4" "$InputMp4"
    Write-Host "BGM入り動画を上書きしました。"
} else {
    Write-Error "BGM入りファイルが生成されませんでした。"
}
