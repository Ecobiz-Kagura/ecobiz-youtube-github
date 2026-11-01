$mp4 = Get-ChildItem -File -Filter *.mp4 |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if ($null -eq $mp4) {
    Write-Host "MP4ファイルがありません。"
    exit
}

$mp3 = [System.IO.Path]::ChangeExtension($mp4.FullName, ".mp3")

Write-Host "変換元: $($mp4.Name)"
Write-Host "変換先: $mp3"

ffmpeg -i "$($mp4.FullName)" -vn -codec:a libmp3lame -q:a 2 "$mp3"
