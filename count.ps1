# =================================================================
# PowerShell：today から指定件数ランダム取得（既定：非再帰）
# Mode でカテゴリ切替（Map + token）
# 類似ファイル確認 + スキップ時は done に安全移動（衝突対応）
# 先頭で対象フォルダ内の総ファイル数を表示
# 各処理対象ファイルをフルパスで表示
# 各ファイルごとに経過時間（秒 + mm:ss）＋累計（秒 + mm:ss）を表示
# 最後に *.txt のファイル名リネーム（既存仕様）
# =================================================================

param(
    [ValidateSet(
        'genpatsu','huudo','joyuu','kasyu','marx','sakka','rakugo','shinjuku',
        'tekiya','yakuza','yoshiwara','cyber','kankyou','gijutsu','short'
    )]
    [string]$Mode = '',

    [int]$CopyCount = 20,

    [double]$Threshold = 0.80,

    # AND 条件（すべて含む必要がある）
    [string[]]$MustContain,

    # NOT 条件（含んでいたら除外）
    [string[]]$MustNotContain = @(),

    # 単一ワード指定（例: -Word 環境）
    [string]$Word,

    # Word を番号で選ぶ対話モード（複数番号 OK: 1,3,5）
    [switch]$PromptWord,

    # Modeフォルダ（Map[Mode]）を「探索対象」にする（既定：today直下）
    [switch]$UseModeFolder,

    # today / modeフォルダを再帰で探索する（既定：非再帰）
    [switch]$Recurse,

    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ======== パス設定 ========
$BaseToday = "C:\Users\user\OneDrive\＊【エコビズ】\today"
$trans     = "D:\ecobiz-youtube-uploader\google-trans"
$dest      = (Get-Location).Path

# ======== Map（カテゴリフォルダ） ========
$Map = @{
    genpatsu  = Join-Path $BaseToday '原発'
    huudo     = Join-Path $BaseToday '風土'
    joyuu     = Join-Path $BaseToday '女優'
    kasyu     = Join-Path $BaseToday '歌手'
    marx      = Join-Path $BaseToday 'マルクス'
    sakka     = Join-Path $BaseToday '作家'
    rakugo    = Join-Path $BaseToday '落語'
    shinjuku  = Join-Path $BaseToday '新宿'
    tekiya    = Join-Path $BaseToday 'テキヤ'
    yakuza    = Join-Path $BaseToday 'やくざ'
    yoshiwara = Join-Path $BaseToday '吉原花魁'
    cyber     = Join-Path $BaseToday 'サイバー'
    kankyou   = Join-Path $BaseToday '環境'
    gijutsu   = Join-Path $BaseToday '技術'
    short     = Join-Path $BaseToday 'short'
}

# ======== Mode -> 既定 token（MustContain 未指定のときだけ使う） ========
$ModeToken = @{
    genpatsu  = @('原発')
    huudo     = @('風土')
    joyuu     = @('女優')
    kasyu     = @('歌手')
    marx      = @('マルクス')
    sakka     = @('作家')
    rakugo    = @('落語')
    shinjuku  = @('新宿')
    tekiya    = @('テキヤ')
    yakuza    = @('やくざ')
    yoshiwara = @('吉原','花魁')
    cyber     = @('サイバー')
    kankyou   = @('環境')
    gijutsu   = @('技術')
}

# PromptWord で複数選択したときに OR 条件にするかどうか
$UseOrMustContain = $false

# ======== Word 選択プロンプト（-PromptWord 指定時のみ） ========
if ($PromptWord) {
    # ModeToken の全トークンを一覧化（重複削除）
    $menuWords = @()
    foreach ($vals in $ModeToken.Values) {
        $menuWords += $vals
    }
    $menuWords = $menuWords | Sort-Object -Unique

    # === Word 別 ファイル件数 ===
    $searchRoot = if ($UseModeFolder) { $Map[$Mode] } else { $BaseToday }

    if (Test-Path -LiteralPath $searchRoot) {
        $allTodayForCount = if ($Recurse) {
            Get-ChildItem -LiteralPath $searchRoot -File -Recurse
        } else {
            Get-ChildItem -LiteralPath $searchRoot -File
        }

        Write-Host ""
        Write-Host "=== Word 別 ファイル件数 ===" -ForegroundColor Cyan
        foreach ($w in $menuWords) {
            $escaped = [regex]::Escape($w)
            $cnt = ($allTodayForCount | Where-Object { $_.Name -match $escaped }).Count
            Write-Host ("  {0,-6} : {1,3} 件" -f $w, $cnt) -ForegroundColor Gray
        }
        Write-Host ""
    }
    else {
        Write-Host ("=== Word 別ファイル件数: ルートが見つかりません: {0}" -f $searchRoot) -ForegroundColor Yellow
        Write-Host ""
    }

    Write-Host "=== Word 選択（複数可: 例 1,3）===" -ForegroundColor Cyan
    for ($i = 0; $i -lt $menuWords.Count; $i++) {
        Write-Host ("[{0}] {1}" -f ($i + 1), $menuWords[$i])
    }
    Write-Host "[0] 手入力" -ForegroundColor Yellow

    $sel = Read-Host ("番号を入力してください (0?{0} / カンマ区切り可 / Enterでスキップ)" -f $menuWords.Count)

    if (-not [string]::IsNullOrWhiteSpace($sel)) {

        # カンマ区切りを処理
        $parts = $sel.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' }

        if ($parts.Count -gt 0) {
            $selectedWords = @()

            foreach ($p in $parts) {
                $num = [int]$p

                if ($num -eq 0) {
                    # 手入力（複数可: 空白区切り）
                    $manual = Read-Host "Word を入力してください（複数可: 空白区切り）"
                    if (-not [string]::IsNullOrWhiteSpace($manual)) {
                        $selectedWords += ($manual.Split() | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
                    }
                }
                elseif ($num -ge 1 -and $num -le $menuWords.Count) {
                    $selectedWords += $menuWords[$num - 1]
                }
            }

            # 重複削除
            $selectedWords = $selectedWords | Sort-Object -Unique

            if ($selectedWords.Count -gt 0) {
                # PromptWord で選んだときは MustContain に直接入れる
                $Word = $null
                $MustContain = $selectedWords

                # 2つ以上選ばれたときは OR 条件とみなす
                if ($selectedWords.Count -gt 1) {
                    $UseOrMustContain = $true
                }
                else {
                    $UseOrMustContain = $false
                }

                Write-Host ("選択された Word: {0}" -f ($selectedWords -join ", ")) -ForegroundColor Green
            }
        }
    }
}

# ======== MustContain の最終決定 ========
if (-not $PSBoundParameters.ContainsKey('MustContain') -and (-not $MustContain -or $MustContain.Count -eq 0)) {
    if (-not [string]::IsNullOrWhiteSpace($Word)) {
        # Word があれば、その単一ワードを MustContain に
        $MustContain = @($Word)
    }
    else {
        # 従来通り ModeToken を使う
        $MustContain = $ModeToken[$Mode]
    }
}

# ======== 探索対象フォルダ決定 ========
$src  = if ($UseModeFolder) { $Map[$Mode] } else { $BaseToday }
$done = Join-Path $src 'done'  # done は探索対象フォルダ配下

# ======== 関数 ========
function Normalize-Name([string]$s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return "" }
    $t = $s.Trim().ToLower().Normalize([System.Text.NormalizationForm]::FormKC)
    return ($t -replace '[\s\-\._\(\)\[\]【】「」『」、。・/\\]+','')
}

function Matches-AllTokens([string]$name, [string[]]$tokens) {
    if (-not $tokens -or $tokens.Count -eq 0) { return $true }
    foreach ($tok in $tokens) {
        if ([string]::IsNullOrWhiteSpace($tok)) { continue }
        $pat = [regex]::Escape($tok.Trim())
        if (-not ($name -match $pat)) { return $false }
    }
    return $true
}

function Matches-AnyTokens([string]$name, [string[]]$tokens) {
    if (-not $tokens -or $tokens.Count -eq 0) { return $true }
    foreach ($tok in $tokens) {
        if ([string]::IsNullOrWhiteSpace($tok)) { continue }
        $pat = [regex]::Escape($tok.Trim())
        if ($name -match $pat) { return $true }
    }
    return $false
}

function Matches-NoneTokens([string]$name, [string[]]$tokens) {
    if (-not $tokens -or $tokens.Count -eq 0) { return $true }
    foreach ($tok in $tokens) {
        if ([string]::IsNullOrWhiteSpace($tok)) { continue }
        $pat = [regex]::Escape($tok.Trim())
        if ($name -match $pat) { return $false }
    }
    return $true
}

function Get-NormalizedSimilarity([string]$a, [string]$b) {
    $a = [string]$a; $b = [string]$b
    $la = [int]$a.Length; $lb = [int]$b.Length
    if ($la -eq 0 -and $lb -eq 0) { return 1.0 }
    if ($la -eq 0 -or  $lb -eq 0) { return 0.0 }

    $prev = New-Object int[] ($lb + 1)
    $curr = New-Object int[] ($lb + 1)
    for ($j = 0; $j -le $lb; $j++) { $prev[$j] = $j }

    for ($i = 1; $i -le $la; $i++) {
        $curr[0] = $i
        $ai = $a[$i - 1]
        for ($j = 1; $j -le $lb; $j++) {
            $cost = if ($ai -eq $b[$j - 1]) { 0 } else { 1 }
            $curr[$j] = [Math]::Min(
                [Math]::Min($prev[$j] + 1, $curr[$j - 1] + 1),
                $prev[$j - 1] + $cost
            )
        }
        $tmp = $prev; $prev = $curr; $curr = $tmp
    }

    $dist = $prev[$lb]
    $maxLen = [Math]::Max($la, $lb)
    return 1.0 - ($dist / [double]$maxLen)
}

function Safe-MoveToDone([IO.FileInfo]$srcFile, [string]$doneDir, [switch]$WhatIf) {
    if (-not (Test-Path -LiteralPath $doneDir)) {
        New-Item -ItemType Directory -Path $doneDir | Out-Null
    }
    $base   = [IO.Path]::GetFileNameWithoutExtension($srcFile.Name)
    $ext    = [IO.Path]::GetExtension($srcFile.Name)
    $target = Join-Path $doneDir $srcFile.Name
    $n = 1
    while (Test-Path -LiteralPath $target) {
        $target = Join-Path $doneDir ("{0}({1}){2}" -f $base, $n, $ext)
        $n++
    }
    Move-Item -LiteralPath $srcFile.FullName -Destination $target -WhatIf:$WhatIf
    return $target
}

function Show-StepTime(
    [System.Diagnostics.Stopwatch]$swOne,
    [System.Diagnostics.Stopwatch]$swAll
) {
    $swOne.Stop()

    $oneSec = $swOne.Elapsed.TotalSeconds
    $allSec = $swAll.Elapsed.TotalSeconds

    $oneTS  = [TimeSpan]::FromSeconds($oneSec)
    $allTS  = [TimeSpan]::FromSeconds($allSec)

    Write-Host (
        "    経過: {0:N1}s ({1:mm\:ss}) / 累計: {2:N1}s ({3:mm\:ss})" -f `
        $oneSec, $oneTS, $allSec, $allTS
    ) -ForegroundColor DarkGray
}

# ===== 全体タイマー開始 =====
$swAll = [System.Diagnostics.Stopwatch]::StartNew()

# ===== ログ（モード・パス） =====
Write-Host ("=== Mode: {0} / UseModeFolder: {1} / Recurse: {2} ===" -f $Mode, $UseModeFolder.IsPresent, $Recurse.IsPresent) -ForegroundColor Cyan
Write-Host ("=== src: {0}" -f $src) -ForegroundColor DarkCyan
Write-Host ("=== Map[{0}]: {1}" -f $Mode, $Map[$Mode]) -ForegroundColor DarkGray
Write-Host ("=== MustContain: {0}" -f ($MustContain -join ",")) -ForegroundColor DarkGray
Write-Host ("=== MustNotContain: {0}" -f ($MustNotContain -join ",")) -ForegroundColor DarkGray
Write-Host ("=== MustContain条件: {0}" -f ($(if($UseOrMustContain){"OR"}else{"AND"}))) -ForegroundColor DarkGray

# ===== 対象フォルダのファイル数を表示 =====
if (-not (Test-Path -LiteralPath $src)) { throw "元ディレクトリが見つかりません: $src" }

$allToday = if ($Recurse) {
    Get-ChildItem -LiteralPath $src -File -Recurse
} else {
    Get-ChildItem -LiteralPath $src -File
}

Write-Host ("=== 対象フォルダ内のファイル数: {0} 件 ===" -f $allToday.Count) -ForegroundColor Cyan

# ===== 抽出（MustContain AND/OR / MustNotContain NOT） =====
$srcFiles = $allToday | Where-Object {
    $name = $_.Name
    $matchContain = if ($UseOrMustContain) {
        Matches-AnyTokens -name $name -tokens $MustContain
    } else {
        Matches-AllTokens -name $name -tokens $MustContain
    }
    $matchContain -and (Matches-NoneTokens -name $name -tokens $MustNotContain)
}

if (-not $srcFiles -or $srcFiles.Count -eq 0) {
    Write-Host "条件を満たすファイルがありません。" -ForegroundColor Yellow
    $swAll.Stop()
    return
}

$pickCount   = [Math]::Min($CopyCount, $srcFiles.Count)
$randomFiles = Get-Random -InputObject $srcFiles -Count $pickCount

Write-Host ("=== 抽出対象 {0} 件 ===" -f $pickCount) -ForegroundColor Cyan
$randomFiles | ForEach-Object { Write-Host ("  - " + $_.FullName) -ForegroundColor Gray }

# ===== 類似チェック準備 =====
$doneFiles  = if (Test-Path -LiteralPath $done)  { Get-ChildItem -LiteralPath $done  -File -Recurse }  else { @() }
$transFiles = if (Test-Path -LiteralPath $trans) { Get-ChildItem -LiteralPath $trans -File -Recurse } else { @() }

$allIndex = foreach ($f in ($doneFiles + $transFiles)) {
    [PSCustomObject]@{
        Path     = $f.FullName
        Name     = $f.Name
        NormName = (Normalize-Name $f.Name)
        Source   = if ($f.FullName -like "$trans*") { "google-trans" } else { "done" }
    }
}

# ===== 類似検索を軽くする簡易バケツ =====
$bucket = @{}
foreach ($d in $allIndex) {
    $n = $d.NormName
    if ([string]::IsNullOrWhiteSpace($n)) { continue }
    $key = if ($n.Length -ge 2) { $n.Substring(0,2) } else { $n }
    if (-not $bucket.ContainsKey($key)) {
        $bucket[$key] = New-Object System.Collections.Generic.List[object]
    }
    $bucket[$key].Add($d) | Out-Null
}

$thPct = [Math]::Round($Threshold*100,0)
Write-Host ("=== 類似判定しきい値: {0}% ===" -f $thPct) -ForegroundColor DarkCyan

$copied=0; $skipped=0; $movedToDone=0; $idx=0
# ★ コピーしたファイルの一覧
$copiedFiles = @()

foreach ($srcFile in $randomFiles) {
    $idx++
    $swOne = [System.Diagnostics.Stopwatch]::StartNew()

    $srcName = $srcFile.Name
    $srcNorm = Normalize-Name $srcName

    Write-Host ("[{0}/{1}] チェック中: {2}" -f $idx, $pickCount, $srcFile.FullName) -ForegroundColor DarkCyan

    # ===== best探索（候補を絞ってから距離計算） =====
    $bestSim=0.0; $best=$null

    $k = if ($srcNorm.Length -ge 2) { $srcNorm.Substring(0,2) } else { $srcNorm }
    $cands = @()
    if ($bucket.ContainsKey($k)) { $cands += $bucket[$k] }

    if ($cands.Count -lt 50 -and $srcNorm.Length -ge 1) {
        $k1 = $srcNorm.Substring(0,1)
        foreach ($kk in $bucket.Keys) {
            if ($kk.StartsWith($k1)) { $cands += $bucket[$kk] }
        }
    }
    if ($cands.Count -eq 0) { $cands = $allIndex }

    $lenA = $srcNorm.Length
    $cands = $cands | Where-Object {
        $lenB = $_.NormName.Length
        [Math]::Abs($lenA - $lenB) -le 20
    }

    foreach ($d in $cands) {
        $sim = Get-NormalizedSimilarity $srcNorm $d.NormName
        if ($sim -gt $bestSim) { $bestSim=$sim; $best=$d }
        if ($bestSim -ge 1.0) { break }
    }

    # ===== short条件 =====
    $srcHasShort  = ($srcName -match '(?i)short')
    $bestHasShort = ($best -and $best.Name -match '(?i)short')
    $xorShort     = ($srcHasShort -xor $bestHasShort)

    $simNoShort = 0.0
    if ($best) {
        $srcNoShort  = Normalize-Name ($srcName  -replace '(?i)short','')
        $bestNoShort = Normalize-Name ($best.Name -replace '(?i)short','')
        $simNoShort  = Get-NormalizedSimilarity $srcNoShort $bestNoShort
    }

    try {
        # 片側のみ short かつ 類似度高い → コピー
        if ($best -and $xorShort -and (($bestSim -ge $Threshold) -or ($simNoShort -ge $Threshold))) {
            Write-Host ("  → 'short' 片側一致：コピー（類似:{0:F1}% / 相手:{1} [{2}]）" -f ($bestSim*100), $best.Name, $best.Source) -ForegroundColor Green
            Copy-Item -LiteralPath $srcFile.FullName -Destination $dest -Force -WhatIf:$WhatIf
            $copied++
            # ★ コピー先パスを記録
            $copiedFiles += (Join-Path $dest $srcFile.Name)
            Show-StepTime $swOne $swAll
            continue
        }

        # 類似しきい値以上 → done に移動
        if ($best -and $bestSim -ge $Threshold) {
            $moved = Safe-MoveToDone -srcFile $srcFile -doneDir $done -WhatIf:$WhatIf
            Write-Host ("  → SKIP: 類似 {0:F1}% / 相手:{1} [{2}] → done: {3}" -f ($bestSim*100), $best.Name, $best.Source, $moved) -ForegroundColor Yellow
            $skipped++; $movedToDone++
            Show-StepTime $swOne $swAll
            continue
        }

        # short 除去後の類似が高い → done に移動
        if ($best -and $simNoShort -ge $Threshold) {
            $moved = Safe-MoveToDone -srcFile $srcFile -doneDir $done -WhatIf:$WhatIf
            Write-Host ("  → SKIP: short除去類似 {0:F1}% / 相手:{1} [{2}] → done: {3}" -f ($simNoShort*100), $best.Name, $best.Source, $moved) -ForegroundColor Yellow
            $skipped++; $movedToDone++
            Show-StepTime $swOne $swAll
            continue
        }

        # 類似なし → コピー
        Copy-Item -LiteralPath $srcFile.FullName -Destination $dest -Force -WhatIf:$WhatIf
        Write-Host "  → 類似ファイルなし。コピーしました。" -ForegroundColor Green
        $copied++
        # ★ コピー先パスを記録
        $copiedFiles += (Join-Path $dest $srcFile.Name)
        Show-StepTime $swOne $swAll
    }
    catch {
        Write-Host ("  → 処理失敗: {0}" -f $_.Exception.Message) -ForegroundColor Red
        Show-StepTime $swOne $swAll
    }
}

Write-Host ""

# ★ 最後に、コピーしたファイル一覧を表示
if ($copiedFiles.Count -gt 0) {
    Write-Host "=== コピーしたファイル一覧 ===" -ForegroundColor Green
    foreach ($p in $copiedFiles) {
        Write-Host ("  " + $p) -ForegroundColor Gray
    }
} else {
    Write-Host "コピーされたファイルはありません。" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== サマリ ===" -ForegroundColor DarkCyan
Write-Host ("  コピー             : {0} 件" -f $copied) -ForegroundColor Green
Write-Host ("  スキップ（done移動）: {0} 件（類似≧{1}%）" -f $skipped, $thPct) -ForegroundColor Yellow
Write-Host ("    → 実際に移動した : {0} 件" -f $movedToDone) -ForegroundColor Yellow

# 第1部の累計表示（秒 + mm:ss）
$allSecMid = $swAll.Elapsed.TotalSeconds
$allTSMid  = [TimeSpan]::FromSeconds($allSecMid)
Write-Host ("=== 第1部 累計: {0:N1}s ({1:mm\:ss}) ===" -f $allSecMid, $allTSMid) -ForegroundColor Cyan

################## ここから txt ファイル名リネーム ##################

$ErrorActionPreference = 'Stop'

# ★ Count エラー対策：必ず配列化
$files = @(Get-ChildItem -File -Filter *.txt)
if (-not $files) {
    Write-Host "対象ファイル (*.txt) が見つかりません。"
    $swAll.Stop()
    return
}

$total      = $files.Count
$renamed    = 0
$skipRename = 0
$conflicted = 0

for ($i = 0; $i -lt $total; $i++) {
    $swOne    = [System.Diagnostics.Stopwatch]::StartNew()
    $f        = $files[$i]
    $nameOrig = $f.Name

    # 正規化 + 置換チェーン（1行）
    $nameNew = ($nameOrig.Normalize([System.Text.NormalizationForm]::FormKC) `
        -replace '　','' `
        -replace ' ','_' `
        -replace '[\uFF5E\u301C\u223C\u2053]','_' `
        -replace '[\u2010-\u2015\u2212]','_' `
        -replace '[<>:"/\\|?*]','_' `
        -replace '[?？]','_' `
        -replace '・','_' `
        -replace '「','_' `
        -replace '」','_' `
        -replace 'ー','_' `
        -replace '_+','_' `
        -replace '^_+|_+$','' `
        -replace '、','')

    # 進捗（100%到達）
    $percent = [int]((($i + 1) / [double]$total) * 100)
    $status  = "{0}/{1} 処理中: {2}" -f ($i+1), $total, $nameOrig
    Write-Progress -Activity "ファイル名リネーム中" -Status $status -PercentComplete $percent

    if ($nameNew -eq $nameOrig) {
        $skipRename++
        Show-StepTime $swOne $swAll
        continue
    }

    $targetPath = Join-Path -Path $f.DirectoryName -ChildPath $nameNew
    try {
        if (Test-Path -LiteralPath $targetPath) {
            $base = [IO.Path]::GetFileNameWithoutExtension($nameNew)
            $ext  = [IO.Path]::GetExtension($nameNew)
            $n = 1
            do {
                $candName = '{0}({1}){2}' -f $base, $n, $ext
                $candPath = Join-Path -Path $f.DirectoryName -ChildPath $candName
                $n++
            } while (Test-Path -LiteralPath $candPath)

            Rename-Item -LiteralPath $f.FullName -NewName $candName -WhatIf:$WhatIf
            Write-Host ("[conflict] {0} -> {1}" -f $nameOrig, $candName)
            $conflicted++; $renamed++
            Show-StepTime $swOne $swAll
            continue
        }
        else {
            Rename-Item -LiteralPath $f.FullName -NewName $nameNew -WhatIf:$WhatIf
            Write-Host ("[renamed ] {0} -> {1}" -f $nameOrig, $nameNew)
            $renamed++
            Show-StepTime $swOne $swAll
            continue
        }
    }
    catch {
        Write-Host ("[ERROR  ] {0} -> (failed) : {1}" -f $nameOrig, $_.Exception.Message) -ForegroundColor Red
        Show-StepTime $swOne $swAll
        continue
    }
}

Write-Progress -Activity "ファイル名リネーム中" -Completed

Write-Host "`n===== サマリー ====="
Write-Host ("対象        : {0} 件" -f $total)
Write-Host ("リネーム    : {0} 件" -f $renamed)
Write-Host ("衝突回避    : {0} 件" -f $conflicted)
Write-Host ("変更なし    : {0} 件" -f $skipRename)

./cp-joyuu.ps1

# ===== 全体タイマー終了（秒 + mm:ss）=====
$swAll.Stop()
$allSec = $swAll.Elapsed.TotalSeconds
$allTS  = [TimeSpan]::FromSeconds($allSec)
Write-Host ("総処理時間  : {0:N1}s ({1:mm\:ss})" -f $allSec, $allTS) -ForegroundColor Cyan