param (
    [Parameter(Mandatory = $true)]
    [string]$InputFile  # 例: myvideo.mp4
)

# ffmpeg.exe の存在確認
if (-not (Get-Command "ffmpeg" -ErrorAction SilentlyContinue)) {
    Write-Host "? ffmpeg が見つかりません。PATH を確認してください。"
    exit 1
}

# 入力ファイルの存在確認
if (-not (Test-Path $InputFile)) {
    Write-Host "? 入力ファイル '$InputFile' が存在しません。"
    exit 1
}

# 出力ファイル名（"_3x" を追加）
$BaseName = [System.IO.Path]::GetFileNameWithoutExtension($InputFile)
$Extension = [System.IO.Path]::GetExtension($InputFile)
$OutputFile = "$BaseName`_3x$Extension"

# 一時リストファイル作成
$tempListFile = "concat_list.txt"
@(
    "file '$InputFile'"
    "file '$InputFile'"
    "file '$InputFile'"
) | Out-File -Encoding ASCII -FilePath $tempListFile

# FFmpeg 実行（連結）
$ffmpegCmd = "ffmpeg -y -f concat -safe 0 -i `"$tempListFile`" -c copy `"$OutputFile`""
Write-Host "? 実行中: $ffmpegCmd"
Invoke-Expression $ffmpegCmd

# 一時ファイル削除
Remove-Item $tempListFile -Force

Write-Host "? 完了: '$OutputFile' を作成しました。"
