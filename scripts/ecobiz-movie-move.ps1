
$Root = "D:\【エコビズ】\【動画】"
$DownloadDir = "C:\Users\user\Downloads"

# 1. ディレクトリ一覧を取得
$Dirs = @(Get-ChildItem -LiteralPath $Root -Directory -Recurse |
    Sort-Object FullName)

if ($Dirs.Count -eq 0) {
    Write-Host "ディレクトリがありません。"
    return
}

Write-Host "`n===== ディレクトリ一覧 =====" -ForegroundColor Cyan

for ($i = 0; $i -lt $Dirs.Count; $i++) {
    $RelativePath = $Dirs[$i].FullName.Substring($Root.Length).TrimStart('\')
    Write-Host ("[{0}] {1}" -f ($i + 1), $RelativePath)
}

# 2. 移動先を選択
$Choice = Read-Host "`n移動先の番号を入力 (0=キャンセル)"
$Number = 0

if (-not [int]::TryParse($Choice, [ref]$Number) -or
    $Number -lt 1 -or $Number -gt $Dirs.Count) {
    Write-Host "キャンセルまたは無効な番号です。"
    return
}

$Destination = $Dirs[$Number - 1].FullName

Set-Location -LiteralPath $Destination
Write-Host "`n移動先: $Destination" -ForegroundColor Green

# 3. Downloadsから作成日時が新しい4ファイルを取得
$LatestFiles = @(Get-ChildItem -LiteralPath $DownloadDir -File |
    Sort-Object CreationTime -Descending |
    Select-Object -First 4)

if ($LatestFiles.Count -eq 0) {
    Write-Host "コピー対象ファイルがありません。"
    return
}

Write-Host "`n===== コピー対象（最新4件） =====" -ForegroundColor Cyan

foreach ($File in $LatestFiles) {
    Write-Host ("{0}  {1}" -f
        $File.CreationTime.ToString("yyyy/MM/dd HH:mm:ss"),
        $File.Name)
}

# 4. コピー実行確認
$Answer = Read-Host "`nこれらのファイルをコピーしますか？ (Y/N)"

if ($Answer -notmatch '^[Yy]$') {
    Write-Host "コピーをキャンセルしました。"
    return
}

# 5. ファイルをコピー
foreach ($File in $LatestFiles) {
    $Target = Join-Path $Destination $File.Name

    if (Test-Path -LiteralPath $Target) {
        Write-Host "同名ファイルが存在するためスキップ: $($File.Name)" -ForegroundColor Yellow
        continue
    }

    try {
        Copy-Item -LiteralPath $File.FullName `
                  -Destination $Target `
                  -ErrorAction Stop

        Write-Host "コピー完了: $($File.Name)" -ForegroundColor Green
    }
    catch {
        Write-Host "コピー失敗: $($File.Name) - $_" -ForegroundColor Red
    }
}

Write-Host "`n処理終了。現在のディレクトリ: $(Get-Location)"
