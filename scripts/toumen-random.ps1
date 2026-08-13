# 検索元
$RootDir = "C:\Users\flare\OneDrive\＊【エコビズ】"

# コピー先
$DestDir = "C:\Users\flare\OneDrive\＊【エコビズ】\＊【当面】"

# コピー先がなければ作成
if (-not (Test-Path -LiteralPath $DestDir)) {
    New-Item -ItemType Directory -Path $DestDir | Out-Null
}

Write-Host "コピー先を初期化します:"
Write-Host $DestDir
Write-Host ""

# ----------------------------------------
# コピー先以下のファイルをすべて削除
# ----------------------------------------

Get-ChildItem `
    -LiteralPath $DestDir `
    -File `
    -Recurse `
    -ErrorAction SilentlyContinue |
Remove-Item -Force

Write-Host "既存ファイルをすべて削除しました。"
Write-Host ""

# ----------------------------------------
# PDFファイルを再帰検索
# ----------------------------------------

$Files = Get-ChildItem `
    -LiteralPath $RootDir `
    -File `
    -Recurse `
    -Filter "*.pdf"

Write-Host "対象PDFファイル数: $($Files.Count)"

if ($Files.Count -eq 0) {
    Write-Host "PDFファイルがありません。"
    exit
}

# ----------------------------------------
# 最大10個をランダム選択
# ----------------------------------------

$Count = [Math]::Min(10, $Files.Count)

$SelectedFiles = $Files | Get-Random -Count $Count

Write-Host ""
Write-Host "ランダムに選択したPDF:"
Write-Host ""

# ----------------------------------------
# コピー
# ----------------------------------------

foreach ($File in $SelectedFiles) {

    Write-Host $File.FullName

    Copy-Item `
        -LiteralPath $File.FullName `
        -Destination $DestDir `
        -Force
}

Write-Host ""
Write-Host "$Count 個のPDFファイルをコピーしました。"
Write-Host "コピー先: $DestDir"