# ============================================
# 条件
# ・「ダウンロード」を含むディレクトリ配下
# ・PDF
# ・「Rあり」は「Rを含む かつ 全角＊を含まない」
# ・選択式
# ============================================

$base = "C:\Users\user\OneDrive\＊【エコビズ】"

# PDF取得
$files = Get-ChildItem $base -Directory -Recurse |
Where-Object { $_.Name -like "*ダウンロード*" } |
Get-ChildItem -File -Recurse -Filter *.pdf

# 分類
$withR = $files | Where-Object {
    $_.Name -match 'R' -and $_.Name -notmatch '＊'
}

$withoutR = $files | Where-Object {
    $_.Name -notmatch 'R'
}

# 選択
Write-Host "表示を選択してください:"
Write-Host "1 = Rを含む（かつ＊なし）"
Write-Host "2 = Rを含まない"
Write-Host "3 = 両方"
$choice = Read-Host "番号を入力"

switch ($choice) {
    "1" {
        Write-Host "`n===== Rを含む（＊なし） ====="
        $withR | Select-Object -ExpandProperty FullName
        Write-Host "`n件数: $($withR.Count)"
    }
    "2" {
        Write-Host "`n===== Rを含まない ====="
        $withoutR | Select-Object -ExpandProperty FullName
        Write-Host "`n件数: $($withoutR.Count)"
    }
    "3" {
        Write-Host "`n===== Rを含む（＊なし） ====="
        $withR | Select-Object -ExpandProperty FullName

        Write-Host "`n===== Rを含まない ====="
        $withoutR | Select-Object -ExpandProperty FullName

        Write-Host "`n件数:"
        Write-Host "Rあり(＊なし): $($withR.Count)"
        Write-Host "Rなし        : $($withoutR.Count)"
    }
    default {
        Write-Host "無効な入力です"
    }
}