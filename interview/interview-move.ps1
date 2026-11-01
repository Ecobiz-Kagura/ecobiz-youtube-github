$base = "D:\【エコビズ】\インタビュー"
$base2 = "D:\"

# 最新ファイルがあるディレクトリを取得
$latestDir = Get-ChildItem $base -Recurse -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1 -ExpandProperty DirectoryName

if (-not $latestDir) {
    Write-Host "ファイルが見つかりませんでした。"
    exit
}

# 最新ファイルのディレクトリへ移動
Set-Location $latestDir
Write-Host "移動しました: $latestDir"

# ベースディレクトリ直下の .ps1 をコピー
Get-ChildItem $base2 -File -Filter inter*.ps1 | ForEach-Object {
    Copy-Item $_.FullName -Destination $latestDir -Force
    Write-Host "コピー: $($_.Name)"
}

# ベースディレクトリ直下の .ps1 をコピー
Get-ChildItem $base2 -File -Filter whis*.ps1 | ForEach-Object {
    Copy-Item $_.FullName -Destination $latestDir -Force
    Write-Host "コピー: $($_.Name)"
}


Write-Host "完了しました。"