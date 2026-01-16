# ============================
# Type を毎回ランダムに変えて、合計 Count 件コピー（完全版）
# - 直下のみ（非再帰）
# - 1件ごとに Type をランダム選択（その都度 type を変える）
# - ファイル名を正規化（行継続 ` は一切使わない）
# - 同名衝突は (1)(2)... で回避
# - StrictMode 最新でも落ちない
# ============================

param(
    [ValidateSet(
        "genpatsu","huudo","joyuu","kasyu","marx","sakka","rakugo","shinjuku",
        "tekiya","yakuza","yoshiwara","cyber","kankyou","gijutsu","random"
    )]
    [string]$Type = "random",

    # ★最終的にコピーされる総件数
    [int]$Count = 3,

    # ★Type の重複を避けたいなら -UniqueType を付ける（任意）
    [switch]$UniqueType
)

$Base = 'C:\Users\user\OneDrive\＊【エコビズ】'

# --- Type → フォルダマッピング（cp-*.ps1 の番号に合わせる）---
$Map = @{
    genpatsu  = Join-Path $Base '原発'        # 1  ./cp-genpatsu.ps1
    huudo     = Join-Path $Base '風土'        # 2  ./cp-huudo.ps1
    joyuu     = Join-Path $Base '女優'        # 3  ./cp-joyuu.ps1
    kasyu     = Join-Path $Base '歌手'        # 4  ./cp-kasyu.ps1
    marx      = Join-Path $Base 'マルクス'    # 5  ./cp-marx.ps1
    sakka     = Join-Path $Base '作家'        # 6  ./cp-sakka.ps1
    rakugo    = Join-Path $Base '落語'        # 7  ./cp-rakugo.ps1
    shinjuku  = Join-Path $Base '新宿'        # 8  ./cp-shinjuku.ps1
    tekiya    = Join-Path $Base 'テキヤ'      # 9  ./cp-tekiya.ps1
    yakuza    = Join-Path $Base 'やくざ'      # 10 ./cp-yakuza.ps1
    yoshiwara = Join-Path $Base '吉原花魁'    # 11 ./cp-yoshiwara.ps1
    cyber     = Join-Path $Base 'サイバー'    # 12 ./cp-cyber.ps1
    kankyou   = Join-Path $Base '環境'        # 13 ./cp-kankyou.ps1
    gijutsu   = Join-Path $Base '技術'        # 14 ./cp-gijutsu.ps1
}

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Destination = (Get-Location).Path

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

# --- Type一覧（random 自体は除外）---
$Types = @($Map.Keys)

# --- コピー実行（1件ごとに Type を変える）---
$copied = 0
$attempt = 0
$maxAttempt = [Math]::Max(50, $Count * 20)  # 失敗が続いても無限ループしない

# UniqueType 用（使う時だけ）
$remainingTypes = @($Types)

Write-Host ("Destination={0}" -f $Destination)
Write-Host ("Count(request)={0}" -f $Count)
Write-Host ("Mode=per-file random type (UniqueType={0})" -f $UniqueType.IsPresent)
Write-Host ""

while ($copied -lt $Count -and $attempt -lt $maxAttempt) {
    $attempt++

    # --- Type を選ぶ ---
    if ($UniqueType) {
        if (-not $remainingTypes -or $remainingTypes.Count -eq 0) {
            Write-Warning "UniqueType 指定ですが、Type が尽きました。これ以上コピーできません。"
            break
        }
        $chosenType = $remainingTypes | Get-Random -Count 1
        # 選んだ Type を除外
        $remainingTypes = @($remainingTypes | Where-Object { $_ -ne $chosenType })
    } else {
        $chosenType = $Types | Get-Random -Count 1
    }

    $Source = $Map[$chosenType]

    if (-not (Test-Path -LiteralPath $Source)) {
        Write-Warning ("Source 不存在のためスキップ: Type={0} Source={1}" -f $chosenType, $Source)
        continue
    }

    # --- 直下のみ（非再帰）---
    $files = Get-ChildItem -LiteralPath $Source -File
    if (-not $files -or $files.Count -eq 0) {
        Write-Warning ("空フォルダのためスキップ: Type={0} Source={1}" -f $chosenType, $Source)
        continue
    }

    # --- 1個だけランダム取得（StrictMode対策：配列化不要だが統一）---
    $f = @($files | Get-Random -Count 1)[0]

    # 正規化に失敗しても止めない（元名にフォールバック）
    try { $normalized = Normalize-FileName $f.Name } catch { $normalized = $f.Name }

    $saveName   = Resolve-NameConflict -dir $Destination -fileName $normalized
    $targetPath = Join-Path $Destination $saveName

    $copied++
    Write-Host ("[{0}/{1}] Type={2}" -f $copied, $Count, $chosenType)
    Write-Host ("          SourceFile: {0}" -f $f.FullName)
    Write-Host ("          SaveName  : {0}" -f $saveName)

    Copy-Item -LiteralPath $f.FullName -Destination $targetPath -Force
}

if ($copied -lt $Count) {
    Write-Warning ("完了: {0}件のみコピーしました。（要求={1} / 試行={2}）" -f $copied, $Count, $attempt)
} else {
    Write-Host ("完了: Type を毎回ランダムにして {0} 件コピーしました。" -f $copied)
}
