
# ============================
# 原発フォルダからランダム取得 → カレントへコピー（完全版）
# - 直下のみ（非再帰）
# - ファイル名を正規化（行継続 ` は一切使わない）
# - 同名衝突は (1)(2)... で回避
# - StrictMode 最新でも落ちない（Get-Random -Count 1 を配列化）
# ============================

$Source      = 'C:\Users\user\OneDrive\＊【エコビズ】\地域'
$Destination = (Get-Location).Path
$Count       = 1  # ←ここを 1 / 2 / 45 などに変更

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $Source)) {
    Write-Error "Source が見つかりません: $Source"
    exit 1
}
if (-not (Test-Path -LiteralPath $Destination)) {
    Write-Error "Destination が見つかりません: $Destination"
    exit 1
}
if ($Count -le 0) {
    Write-Host "Count が 0 以下なので何もしません。Count=$Count"
    exit 0
}

# --- 保存用：ファイル名（拡張子保持）を正規化（行継続なしで安定）---
function Normalize-FileName([string]$fileName) {
    if ([string]::IsNullOrWhiteSpace($fileName)) { return $fileName }

    $base = [IO.Path]::GetFileNameWithoutExtension($fileName)
    $ext  = [IO.Path]::GetExtension($fileName)

    $n = $base.Normalize([System.Text.NormalizationForm]::FormKC)

    # 置換ルール（順番どおりに適用）
    $rules = @(
        @('　', ''),                           # 全角スペース除去
        @(' ', '_'),                           # 半角スペース→_
        @('[\uFF5E\u301C\u223C\u2053]', '_'),  # 波ダッシュ系→_
        @('[\u2010-\u2015\u2212]', '_'),       # ハイフン/マイナス系→_
        @('[?？]', '_'),
        @('・', '_'),
        @('「', '_'),
        @('」', '_'),
        @('ー', '_'),
        @('[/\\:;*"<>\|]', '_'),              # ファイル名禁則→_
        @('_+', '_'),                          # _ の連続を1つに
        @('^_+|_+$', '')                        # 先頭末尾の _ を除去
    )

    foreach ($r in $rules) {
        $n = $n -replace $r[0], $r[1]
    }

    if ([string]::IsNullOrWhiteSpace($n)) { $n = "noname" }
    return ($n + $ext)
}

# --- 衝突回避：同名があるなら (1)(2)... を付与 ---
function Resolve-NameConflict([string]$dir, [string]$fileName) {
    $cand = $fileName
    $path = Join-Path $dir $cand
    if (-not (Test-Path -LiteralPath $path)) { return $cand }

    $base = [IO.Path]::GetFileNameWithoutExtension($fileName)
    $ext  = [IO.Path]::GetExtension($fileName)

    $n = 1
    do {
        $cand = "{0}({1}){2}" -f $base, $n, $ext
        $path = Join-Path $dir $cand
        $n++
    } while (Test-Path -LiteralPath $path)

    return $cand
}

# --- 直下のみ（非再帰）---
$all = Get-ChildItem -LiteralPath $Source -File
if (-not $all -or $all.Count -eq 0) {
    Write-Host "対象ファイルがありません。"
    exit 0
}

# --- ランダムに $Count 件（Count=1 でも必ず配列にする）---
$k = [Math]::Min($Count, $all.Count)
$pick = @($all | Get-Random -Count $k)

$i = 0
$total = $pick.Count

foreach ($f in $pick) {
    $i++

    # 正規化に失敗しても止めない（元名にフォールバック）
    try { $normalized = Normalize-FileName $f.Name } catch { $normalized = $f.Name }

    $saveName   = Resolve-NameConflict -dir $Destination -fileName $normalized
    $targetPath = Join-Path $Destination $saveName

    Write-Host ("[{0}/{1}] コピー中: {2}" -f $i, $total, $f.FullName)
    Write-Host ("          保存名: {0}" -f $saveName)

    Copy-Item -LiteralPath $f.FullName -Destination $targetPath -Force
}

Write-Host ("完了: ランダム{0}件をコピーしました。" -f $total)
