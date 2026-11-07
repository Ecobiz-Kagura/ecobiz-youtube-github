$src = "C:\Users\user\OneDrive\＊【エコビズ】\インタビュー"

$file = Get-ChildItem -LiteralPath $src -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if ($file) {
    Copy-Item -LiteralPath $file.FullName -Destination (Get-Location) -Force
    Write-Host "コピー完了: $($file.Name)"
} else {
    Write-Host "ファイルが見つかりません"
}