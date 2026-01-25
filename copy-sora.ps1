<#
sora-copy (完全版：途中経過=Write-Progress 対応)
- 使い方例:
  pwsh -NoProfile -ExecutionPolicy Bypass -File .\sora-copy.ps1 -Category おいらん
  pwsh -NoProfile -ExecutionPolicy Bypass -File .\sora-copy.ps1 -Category oiran
  pwsh -NoProfile -ExecutionPolicy Bypass -File .\sora-copy.ps1 -Category サイバー
  pwsh -NoProfile -ExecutionPolicy Bypass -File .\sora-copy.ps1 -Category cyber
  pwsh -NoProfile -ExecutionPolicy Bypass -File .\sora-copy.ps1 -Category テキヤ
  pwsh -NoProfile -ExecutionPolicy Bypass -File .\sora-copy.ps1 -Category tekiya
  pwsh -NoProfile -ExecutionPolicy Bypass -File .\sora-copy.ps1 -Category かしゅ -Root D:\images_for_slide_show

仕様:
- コピー元:   $Root\【カテゴリ】 配下の *.mp4 (再帰)
- コピー先:   $Root 直下のディレクトリのうち、名前にカテゴリを含むもの
            ただし、名前に「【」または「】」を含むディレクトリは対象外
- コピー先配下に「動画」フォルダが無ければ作成
- 同名 mp4 はスキップ
- 途中経過:
  * Write-Progress で「全体(ターゲット)」「各ターゲット内(ファイル)」の二段階進捗を表示
  * Write-Host でも「最初の5件 / 50件ごと / 最後」を表示
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Category,

    [Parameter(Position = 1)]
    [string]$Root = 'D:\images_for_slide_show'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ローマ字 → 表記（必要に応じて追加）
# ※要望反映：cyber と tekiya はカタカナ
$CategoryMap = @{
    "cyber"          = "サイバー"
    "dansei-kasyu"   = "だんせいかしゅ"
    "josei-kasyu"    = "じょせいかしゅ"
    "genpatsu"       = "げんぱつ"
    "gyogyou"        = "ぎょぎょう"
    "joyuu"          = "じょゆう"
    "kabukicho"      = "かぶきちょう"
    "kasyu"          = "かしゅ"
    "kawabe"         = "かわべ"
    "kensetsu"       = "けんせつ"
    "kitatyousen"    = "きたちょうせん"
    "marx"           = "まるくす"
    "oiran"          = "おいらん"
    "recycle"        = "りさいくる"
    "sakka"          = "さっか"
    "souti"          = "そうち"
    "tekiya"         = "テキヤ"
    "tihoutoshi"     = "ちほうとし"
    "wangan"         = "わんがん"
    "yakuza"         = "やくざ"
    "yama"           = "やま"
    "yoshiwara"      = "よしわら"
}

function Resolve-CategoryLabel {
    param([string]$InputCategory)

    $key = $InputCategory.Trim()
    if ([string]::IsNullOrWhiteSpace($key)) { throw "Category が空です。" }

    if ($CategoryMap.ContainsKey($key)) { return $CategoryMap[$key] }

    # ひらがな/カタカナ等で直接指定された場合はそのまま使う
    return $key
}

$CategoryLabel = Resolve-CategoryLabel -InputCategory $Category
$Src = Join-Path $Root "【$CategoryLabel】"

Write-Host "=== 設定 ==="
Write-Host "Root        : $Root"
Write-Host "Category(in): $Category"
Write-Host "Category    : $CategoryLabel"
Write-Host "Src         : $Src"
Write-Host ""

if (-not (Test-Path -LiteralPath $Root)) { throw "Root が見つかりません: $Root" }
if (-not (Test-Path -LiteralPath $Src))  { throw "Src が見つかりません: $Src" }

# 1) コピー元 mp4 を収集
Write-Host "=== [1/4] コピー元 mp4 を収集中 ==="
$srcMp4 = Get-ChildItem -LiteralPath $Src -File -Filter *.mp4 -Recurse
Write-Host ("コピー元 mp4 数: {0}" -f $srcMp4.Count)
if ($srcMp4.Count -eq 0) { throw "コピー元 mp4 が 0 件です: $Src" }

Write-Host "先頭5件（確認）:"
$srcMp4 | Select-Object -First 5 | ForEach-Object { Write-Host ("  " + $_.FullName) }
Write-Host ""

# 2) 対象ディレクトリ（Root直下）を収集：カテゴリを含み、【】を含むディレクトリは除外
Write-Host "=== [2/4] コピー先ディレクトリを収集中（【】は除外） ==="
$targets = Get-ChildItem -LiteralPath $Root -Directory | Where-Object {
    $_.Name -like "*$CategoryLabel*" -and
    $_.Name -notlike "*【*" -and
    $_.Name -notlike "*】*"
}

Write-Host ("対象ディレクトリ数: {0}" -f $targets.Count)
if ($targets.Count -eq 0) {
    throw "コピー先が 0 件です。Root 直下に '*$CategoryLabel*' を含むディレクトリがありません（【】付きは除外）。"
}

Write-Host "対象一覧:"
$targets | ForEach-Object { Write-Host ("  " + $_.FullName) }
Write-Host ""

# 3) 各対象配下に「動画」フォルダが無ければ作成
Write-Host "=== [3/4] '動画' フォルダ確認/作成 ==="
$created = 0
foreach ($t in $targets) {
    $dst = Join-Path $t.FullName '動画'
    if (-not (Test-Path -LiteralPath $dst)) {
        New-Item -ItemType Directory -Path $dst | Out-Null
        Write-Host ("作成: {0}" -f $dst)
        $created++
    } else {
        Write-Host ("既存: {0}" -f $dst)
    }
}
Write-Host ("新規作成数: {0}" -f $created)
Write-Host ""

# 4) コピー実行（同名スキップ）＋進捗
Write-Host "=== [4/4] mp4 コピー開始（同名はスキップ） ==="
$totalTargets = $targets.Count
$totalSrc     = $srcMp4.Count

$copiedTotal  = 0
$skippedTotal = 0
$errorsTotal  = 0

# Stopwatch（経過時間表示）
$sw = [System.Diagnostics.Stopwatch]::StartNew()

# Write-Progress の Activity ID（親=1 / 子=2）
$progressParentId = 1
$progressChildId  = 2

$ti = 0
foreach ($t in $targets) {
    $ti++
    $dst = Join-Path $t.FullName '動画'

    # 親（ターゲット）進捗
    $pctTarget = [Math]::Floor(($ti - 1) / [Math]::Max(1, $totalTargets) * 100)
    Write-Progress -Id $progressParentId -Activity "コピー全体（カテゴリ: $CategoryLabel）" `
        -Status ("ターゲット {0}/{1}  経過 {2}" -f ($ti-1), $totalTargets, $sw.Elapsed.ToString()) `
        -PercentComplete $pctTarget

    Write-Host ""
    Write-Host ("--- コピー先 [{0}/{1}] {2}" -f $ti, $totalTargets, $dst)

    $copiedThis  = 0
    $skippedThis = 0
    $errorsThis  = 0

    # 既存ファイル名をセット化（高速）
    $existing = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    Get-ChildItem -LiteralPath $dst -File -Filter *.mp4 | ForEach-Object { [void]$existing.Add($_.Name) }

    $si = 0
    foreach ($f in $srcMp4) {
        $si++

        # 子（ファイル）進捗：毎回更新（重いなら 10件ごと等に変えてOK）
        $pctFile = [Math]::Floor(($si / [Math]::Max(1, $totalSrc)) * 100)
        Write-Progress -Id $progressChildId -ParentId $progressParentId `
            -Activity ("ターゲット {0}/{1}: {2}" -f $ti, $totalTargets, $t.Name) `
            -Status ("ファイル {0}/{1}  copied={2} skipped={3} errors={4}  経過 {5}" -f $si, $totalSrc, $copiedThis, $skippedThis, $errorsThis, $sw.Elapsed.ToString()) `
            -PercentComplete $pctFile

        $out = Join-Path $dst $f.Name

        if ($existing.Contains($f.Name)) {
            $skippedThis++; $skippedTotal++
            if (($si -le 5) -or ($si % 50 -eq 0) -or ($si -eq $totalSrc)) {
                Write-Host ("  [{0}/{1}] SKIP  {2}" -f $si, $totalSrc, $f.Name)
            }
            continue
        }

        try {
            Copy-Item -LiteralPath $f.FullName -Destination $out -ErrorAction Stop
            [void]$existing.Add($f.Name)
            $copiedThis++; $copiedTotal++
            if (($si -le 5) -or ($si % 50 -eq 0) -or ($si -eq $totalSrc)) {
                Write-Host ("  [{0}/{1}] COPY  {2}" -f $si, $totalSrc, $f.Name)
            }
        } catch {
            $errorsThis++; $errorsTotal++
            Write-Host ("  [{0}/{1}] ERROR {2} : {3}" -f $si, $totalSrc, $f.Name, $_.Exception.Message)
        }
    }

    Write-Host ("このコピー先の進捗まとめ: copied={0}, skipped={1}, errors={2}" -f $copiedThis, $skippedThis, $errorsThis)

    # このターゲットの子プログレスを完了
    Write-Progress -Id $progressChildId -ParentId $progressParentId -Activity "ターゲット処理完了" -Completed
}

# 親プログレスを完了
Write-Progress -Id $progressParentId -Activity "コピー全体完了" -Completed

$sw.Stop()

Write-Host ""
Write-Host "=== 完了 ==="
Write-Host ("対象ディレクトリ数: {0}" -f $totalTargets)
Write-Host ("コピー元 mp4 数     : {0}" -f $totalSrc)
Write-Host ("コピー成功         : {0}" -f $copiedTotal)
Write-Host ("スキップ           : {0}" -f $skippedTotal)
Write-Host ("エラー             : {0}" -f $errorsTotal)
Write-Host ("経過時間           : {0}" -f $sw.Elapsed.ToString())
