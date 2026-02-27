param(
    [Parameter(Mandatory = $true)]
    [string]$SetupScriptPath,   # 例: .\11-eco-setup.ps1

    [Parameter(Mandatory = $true)]
    [string]$TextFilePath       # 例: .\20250511220157-159-廃木材バイオエタノール...解説.txt
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ======================================
# ★ 実行スクリプト／プログラム／パス設定 ★
# ======================================

# メインのエピローグ生成スクリプト
$SCRIPT_RUN_ECO = ".\run-eco-epilogue.ps1"

# 背景動画のルートディレクトリ
$DIR_BG_ROOT = "D:\ecobiz-images"

# SetupScript 名から背景動画名を作るときのルール
# 例)  "10-eco-x.ps1" → "eco" → "D:\ecobiz-images\eco_3x.mp4"
$BG_SUFFIX = "_3x.mp4"  # 末尾につけるサフィックス

# ======================================
# 0) 処理時間計測開始
# ======================================

$sw = [System.Diagnostics.Stopwatch]::StartNew()

Write-Host "=== Runner (Auto Video) ==="
Write-Host "Setup Script: $SetupScriptPath"
Write-Host "Text File:   $TextFilePath"
Write-Host ""

# ======================================
# 1) StrictMode 対策：未定義変数を先に用意
# ======================================

$origBase     = $null
$origLeaf     = $null
$latestVideo  = $null

$global:origBase    = $null
$global:origLeaf    = $null
$global:latestVideo = $null

# Text 由来の origBase を確実に作る
$origLeaf = Split-Path -Leaf $TextFilePath
$origBase = [IO.Path]::GetFileNameWithoutExtension($origLeaf)

$global:origLeaf = $origLeaf
$global:origBase = $origBase

Write-Host "origBase: $origBase"
Write-Host ""

# ======================================
# 2) 背景動画パスの自動推定
# ======================================

# SetupScript のファイル名からベース名を取得
$setupName = [IO.Path]::GetFileNameWithoutExtension($SetupScriptPath)

# 先頭の「数字-」と末尾の「-x」を取り除く例:
#   10-eco-x → eco
$baseMatch = $setupName -replace '^\d+-', '' -replace '-x$', ''

# 背景動画フルパスを組み立て
$backgroundVideo = Join-Path $DIR_BG_ROOT ("{0}{1}" -f $baseMatch, $BG_SUFFIX)

Write-Host "推定された背景動画: $backgroundVideo"
Write-Host ""

# ======================================
# 3) 下準備スクリプト実行
# ======================================

if (Test-Path -LiteralPath $SetupScriptPath) {
    Write-Host "[1/3] 実行中: $SetupScriptPath ..."
    & $SetupScriptPath
    Write-Host "[1/3] 完了。"
} else {
    throw "SetupScript が見つかりません: $SetupScriptPath"
}

# ======================================
# 4) ショート版＋エピローグ生成(run-eco-epilogue.ps1)
# ======================================

if (-not (Test-Path -LiteralPath $TextFilePath)) {
    throw "テキストが見つかりません: $TextFilePath"
}
if (-not (Test-Path -LiteralPath $backgroundVideo)) {
    throw "背景動画が見つかりません: $backgroundVideo"
}

Write-Host "[2/3] 実行中: $SCRIPT_RUN_ECO ..."
Write-Host "       args: `"$TextFilePath`" `"$backgroundVideo`""
& $SCRIPT_RUN_ECO $TextFilePath $backgroundVideo
Write-Host "[2/3] 完了。"

# ======================================
# 5) latestVideo を安全に取得（あれば）
#    ※ run-eco-epilogue.ps1 側で $global:latestVideo を設定している前提
# ======================================

$latestVideoValue = $null

$gv = Get-Variable -Name latestVideo -Scope Global -ErrorAction SilentlyContinue
if ($gv) { $latestVideoValue = $gv.Value }

if (-not $latestVideoValue) {
    $sv = Get-Variable -Name latestVideo -Scope Script -ErrorAction SilentlyContinue
    if ($sv) { $latestVideoValue = $sv.Value }
}

if (-not $latestVideoValue) {
    $lv = Get-Variable -Name latestVideo -Scope Local -ErrorAction SilentlyContinue
    if ($lv) { $latestVideoValue = $lv.Value }
}

$global:latestVideo = $latestVideoValue

if ($latestVideoValue) {
    Write-Host "latestVideo: $latestVideoValue"
} else {
    Write-Host "latestVideo は未設定（または空）でした。"
}

# ======================================
# 6) 処理時間表示
# ======================================

$sw.Stop()
$elapsed = $sw.Elapsed

Write-Host ""
Write-Host "=== すべて完了しました ==="
Write-Host ("処理時間 : {0:00}:{1:00}:{2:00}.{3:000}" -f `
    $elapsed.Hours, $elapsed.Minutes, $elapsed.Seconds, $elapsed.Milliseconds)