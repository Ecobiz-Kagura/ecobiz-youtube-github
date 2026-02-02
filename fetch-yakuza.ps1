# =================================================================
# PowerShell：today直下から指定件数ランダム取得（非再帰）
# 類似ファイル確認 + スキップ時は done に安全移動（衝突対応）
# 先頭で today 内の総ファイル数を表示
# 各処理対象ファイルをフルパスで表示
# ★各ファイルごとに経過時間（秒 + mm:ss）＋累計（秒 + mm:ss）を表示
# =================================================================

param(
    [switch]$WhatIf
)

# ======== 設定 ========

$CopyCount      = 5

# AND 条件（すべて含む必要がある）
$MustContain    = @("やくざ")
# NOT 条件（含んでいたら除外）
$MustNotContain = @("","")

# 類似しきい値
$threshold      = 0.80

###

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$src   = "C:\Users\user\OneDrive\＊【エコビズ】\today"
$done  = "C:\Users\user\OneDrive\＊【エコビズ】\today\done"
$trans = "D:\ecobiz-youtube-uploader\google-trans"    # 類似確認対象
$dest  = (Get-Location).Path                          # コピー先：現在のディレクトリ

# ---------- 関数 ----------
function Normalize-Name([string]$s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return "" }
    $t = $s.Trim().ToLower().Normalize([System.Text.NormalizationForm]::FormKC)
    return ($t -replace '[\s\-\._\(\)\[\]【】「」『』、。・/\\]+','')
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
    $base = [IO.Path]::GetFileNameWithoutExtension($srcFile.Name)
    $ext  = [IO.Path]::GetExtension($srcFile.Name)
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
# ------------------------

# ===== 全体タイマー開始 =====
$swAll = [System.Diagnostics.Stopwatch]::StartNew()

# ===== today 内のファイル数を表示 =====
if (-not (Test-Path -LiteralPath $src)) { throw "元ディレクトリが見つかりません: $src" }

$allToday = Get-ChildItem -LiteralPath $src -File
Write-Host ("=== today内のファイル数: {0} 件 ===" -f $allToday.Count) -ForegroundColor Cyan

# today直下のみ（非再帰）
$srcFiles = $allToday | Where-Object { Matches-AllTokens -name $_.Name -tokens $MustContain }

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

$thPct = [Math]::Round($threshold*100,0)
Write-Host ("=== 類似判定しきい値: {0}% ===" -f $thPct) -ForegroundColor DarkCyan

$copied=0; $skipped=0; $movedToDone=0; $idx=0

foreach ($srcFile in $randomFiles) {
    $idx++
    $swOne = [System.Diagnostics.Stopwatch]::StartNew()

    $srcName = $srcFile.Name
    $srcNorm = Normalize-Name $srcName
    Write-Host ("[{0}/{1}] チェック中: {2}" -f $idx, $pickCount, $srcFile.FullName) -ForegroundColor DarkCyan

    $bestSim=0.0; $best=$null
    foreach ($d in $allIndex) {
        $sim = Get-NormalizedSimilarity $srcNorm $d.NormName
        if ($sim -gt $bestSim) { $bestSim=$sim; $best=$d }
        if ($bestSim -ge 1.0) { break }
    }

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
        if ($best -and $xorShort -and (($bestSim -ge $threshold) -or ($simNoShort -ge $threshold))) {
            Write-Host ("  → 'short' 片側一致：コピー（類似:{0:F1}%）" -f ($bestSim*100)) -ForegroundColor Green
            Copy-Item -LiteralPath $srcFile.FullName -Destination $dest -Force -WhatIf:$WhatIf
            $copied++
            Show-StepTime $swOne $swAll
            continue
        }

        # 類似しきい値以上 → done に移動
        if ($best -and $bestSim -ge $threshold) {
            $moved = Safe-MoveToDone -srcFile $srcFile -doneDir $done -WhatIf:$WhatIf
            Write-Host ("  → SKIP: 類似 {0:F1}% → done に移動: {1}" -f ($bestSim*100), $moved) -ForegroundColor Yellow
            $skipped++; $movedToDone++
            Show-StepTime $swOne $swAll
            continue
        }

        # short 除去後の類似が高い → done に移動
        if ($best -and $simNoShort -ge $threshold) {
            $moved = Safe-MoveToDone -srcFile $srcFile -doneDir $done -WhatIf:$WhatIf
            Write-Host ("  → SKIP: short除去類似 {0:F1}% → done に移動: {1}" -f ($simNoShort*100), $moved) -ForegroundColor Yellow
            $skipped++; $movedToDone++
            Show-StepTime $swOne $swAll
            continue
        }

        # 類似なし → コピー
        Copy-Item -LiteralPath $srcFile.FullName -Destination $dest -Force -WhatIf:$WhatIf
        Write-Host "  → 類似ファイルなし。コピーしました。" -ForegroundColor Green
        $copied++
        Show-StepTime $swOne $swAll
    }
    catch {
        Write-Host ("  → 処理失敗: {0}" -f $_.Exception.Message) -ForegroundColor Red
        Show-StepTime $swOne $swAll
    }
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

$files = Get-ChildItem -File -Filter *.txt
if (-not $files) {
    Write-Host "対象ファイル (*.txt) が見つかりません。"
    $swAll.Stop()
    return
}

$total = $files.Count
$renamed = 0; $skipRename = 0; $conflicted = 0

for ($i = 0; $i -lt $total; $i++) {
    $swOne = [System.Diagnostics.Stopwatch]::StartNew()

    $f = $files[$i]
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
        } else {
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

# ===== 全体タイマー終了（秒 + mm:ss）=====
$swAll.Stop()
$allSec = $swAll.Elapsed.TotalSeconds
$allTS  = [TimeSpan]::FromSeconds($allSec)
Write-Host ("総処理時間  : {0:N1}s ({1:mm\:ss})" -f $allSec, $allTS) -ForegroundColor Cyan
