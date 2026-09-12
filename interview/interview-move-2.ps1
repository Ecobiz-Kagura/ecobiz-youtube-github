$ErrorActionPreference = "Stop"

# ============================================================
# 設定
# ============================================================

$base = "D:\【エコビズ】\インタビュー"
$scriptSource = "D:\ecobiz-youtube-github\interview"

Write-Host ""
Write-Host "============================================================"
Write-Host "インタビュー用ディレクトリ選択"
Write-Host "============================================================"
Write-Host ""

Write-Host "検索元:"
Write-Host $base
Write-Host ""

Write-Host "ディレクトリを検索しています..."
Write-Host ""

# ============================================================
# ディレクトリ一覧取得
# vertical_random_clips をパスに含むものは除外
# ============================================================

$allDirs = Get-ChildItem `
    -LiteralPath $base `
    -Directory `
    -Recurse `
    -ErrorAction SilentlyContinue

Write-Host "検出したディレクトリ数: $($allDirs.Count)"

$dirs = $allDirs |
    Where-Object {
        $_.FullName -notmatch '\\vertical_random_clips(?:\\|$)'
    } |
    Sort-Object FullName

$excludedCount = $allDirs.Count - $dirs.Count

Write-Host "除外したディレクトリ数: $excludedCount"
Write-Host "選択候補数: $($dirs.Count)"
Write-Host ""

if ($dirs.Count -eq 0) {
    Write-Host "選択可能なディレクトリがありません。"
    exit 1
}

# ============================================================
# 番号付き一覧
# ============================================================

Write-Host "============================================================"
Write-Host "移動候補"
Write-Host "============================================================"
Write-Host ""

for ($i = 0; $i -lt $dirs.Count; $i++) {
    Write-Host ("{0,3}. {1}" -f ($i + 1), $dirs[$i].FullName)
}

Write-Host ""

# ============================================================
# 選択
# ============================================================

$choice = Read-Host "移動するディレクトリの番号を入力してください"

if (
    $choice -notmatch '^\d+$' -or
    [int]$choice -lt 1 -or
    [int]$choice -gt $dirs.Count
) {
    Write-Host ""
    Write-Host "正しい番号を入力してください。"
    exit 1
}

$selected = $dirs[[int]$choice - 1]

Write-Host ""
Write-Host "選択:"
Write-Host $selected.FullName

# ============================================================
# ディレクトリ移動
# ============================================================

Write-Host ""
Write-Host "ディレクトリへ移動しています..."

Set-Location -LiteralPath $selected.FullName

Write-Host "移動完了:"
Write-Host (Get-Location).Path

# ============================================================
# コピー元確認
# ============================================================

Write-Host ""
Write-Host "============================================================"
Write-Host "スクリプトコピー"
Write-Host "============================================================"
Write-Host ""

Write-Host "コピー元:"
Write-Host $scriptSource

Write-Host ""
Write-Host "コピー対象を検索しています..."

if (-not (Test-Path -LiteralPath $scriptSource)) {
    Write-Host ""
    Write-Host "コピー元ディレクトリが見つかりません。"
    Write-Host $scriptSource
    exit 1
}

# ============================================================
# 対象スクリプト取得
# ============================================================

$scripts = Get-ChildItem `
    -LiteralPath $scriptSource `
    -File `
    -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Extension -in ".ps1", ".py", ".bat", ".cmd", ".sh"
    }

Write-Host "コピー対象: $($scripts.Count) ファイル"
Write-Host ""

if ($scripts.Count -eq 0) {
    Write-Host "コピー対象のスクリプトがありません。"
    exit 0
}

# ============================================================
# 1ファイルずつコピーして途中経過表示
# ============================================================

$count = 0

foreach ($script in $scripts) {

    $count++

    Write-Host ("[{0}/{1}] コピー中: {2}" -f `
        $count,
        $scripts.Count,
        $script.Name
    )

    Copy-Item `
        -LiteralPath $script.FullName `
        -Destination $selected.FullName `
        -Force
}

# ============================================================
# 完了
# ============================================================

Write-Host ""
Write-Host "============================================================"
Write-Host "完了"
Write-Host "============================================================"

Write-Host ""
Write-Host "移動先:"
Write-Host $selected.FullName

Write-Host ""
Write-Host "コピーしたスクリプト数:"
Write-Host $scripts.Count

Write-Host ""
Write-Host "現在のディレクトリ:"
Write-Host (Get-Location).Path