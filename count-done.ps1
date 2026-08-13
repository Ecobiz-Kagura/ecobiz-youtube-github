# =================================================================
# PowerShell：done から指定件数ランダム取得（既定：非再帰）
# Mode でカテゴリ切替（Map + token）
# 類似ファイル確認
# ★ 類似時も done へ移動せず、カレントディレクトリへそのままコピー
# ★ (1) などは付けない
# 先頭で対象フォルダ内の総ファイル数を表示
# ★ カテゴリ別（ModeTokenキー別）ファイル件数を「件数順にソートして」表示
# ★ 表示番号と選択番号がズレない
# ★ 複数カテゴリ選択は「カテゴリ単位OR」（各カテゴリ内はtoken AND）
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

    [string[]]$MustContain,
    [string[]]$MustNotContain = @(),
    [string]$Word,

    [bool]$PromptWord = $true,

    [switch]$UseModeFolder,
    [switch]$Recurse,

    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ======== パス設定 ========
$BaseToday = "C:\Users\user\OneDrive\＊【エコビズ】\today\done"
$trans     = "D:\ecobiz-youtube-github"
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
    short     = @('short')
}

# ======== 入力の安全化 ========
if ($UseModeFolder) {
    if ([string]::IsNullOrWhiteSpace($Mode)) {
        throw "-UseModeFolder を指定する場合は -Mode を必ず指定してください。"
    }
    if (-not $Map.ContainsKey($Mode)) {
        throw "未知の Mode です: $Mode"
    }
}

# ======== 探索対象フォルダ決定 ========
$src = if ($UseModeFolder) { $Map[$Mode] } else { $BaseToday }

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

function Matches-NoneTokens([string]$name, [string[]]$tokens) {
    if (-not $tokens -or $tokens.Count -eq 0) { return $true }
    foreach ($tok in $tokens) {
        if ([string]::IsNullOrWhiteSpace($tok)) { continue }
        $pat = [regex]::Escape($tok.Trim())
        if ($name -match $pat) { return $false }
    }
    return $true
}

function Matches-AnyTokenGroup([string]$name, [object[]]$groups) {
    if (-not $groups -or $groups.Count -eq 0) { return $true }
    foreach ($g in $groups) {
        if (Matches-AllTokens -name $name -tokens ([string[]]$g)) { return $true }
    }
    return $false
}

function Get-NormalizedSimilarity([string]$a, [string]$b) {
    $a = [string]$a
    $b = [string]$b
    $la = [int]$a.Length
    $lb = [int]$b.Length

    if ($la -eq 0 -and $lb -eq 0) { return 1.0 }
    if ($la -eq 0 -or $lb -eq 0) { return 0.0 }

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
        $tmp = $prev
        $prev = $curr
        $curr = $tmp
    }

    $dist = $prev[$lb]
    $maxLen = [Math]::Max($la, $lb)
    return 1.0 - ($dist / [double]$maxLen)
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

function Get-SourceFiles([string]$root, [switch]$Recurse) {
    if (-not (Test-Path -LiteralPath $root)) { return @() }

    $files = if ($Recurse) {
        @(Get-ChildItem -LiteralPath $root -File -Recurse)
    } else {
        @(Get-ChildItem -LiteralPath $root -File)
    }

    return @($files)
}

# ===== 全体タイマー開始 =====
$swAll = [System.Diagnostics.Stopwatch]::StartNew()

# ===== 対象フォルダの存在確認 =====
if (-not (Test-Path -LiteralPath $src)) {
    throw "元ディレクトリが見つかりません: $src"
}

# ===== カテゴリ選択（PromptWord=true のとき） =====
$MustContainGroups = @()

if ($PromptWord) {
    $allForCount = @(Get-SourceFiles -root $src -Recurse:$Recurse)

    $catMenu = foreach ($k in ($ModeToken.Keys | Sort-Object)) {
        $label = $k
        if ($Map.ContainsKey($k)) {
            $leaf = Split-Path -Path $Map[$k] -Leaf
            if (-not [string]::IsNullOrWhiteSpace($leaf)) { $label = $leaf }
        }

        $tokens = [string[]]$ModeToken[$k]

        $cnt = @(
            $allForCount | Where-Object {
                Matches-AllTokens -name $_.Name -tokens $tokens
            }
        ).Count

        [PSCustomObject]@{
            Key    = $k
            Label  = $label
            Tokens = $tokens
            Count  = [int]$cnt
        }
    }

    $catMenuSorted = @(
        $catMenu | Sort-Object @{Expression='Count';Descending=$true}, @{Expression='Label';Descending=$false}
    )

    Write-Host ""
    Write-Host "=== カテゴリ別 ファイル件数（件数順） ===" -ForegroundColor Cyan
    for ($i = 0; $i -lt $catMenuSorted.Count; $i++) {
        $c = $catMenuSorted[$i]
        $tokStr = ($c.Tokens -join "+")
        Write-Host ("[{0}] {1,-8} : {2,4} 件  (token:{3})" -f ($i+1), $c.Label, $c.Count, $tokStr) -ForegroundColor Gray
    }
    Write-Host "[0] 手入力（Wordを直接入力）" -ForegroundColor Yellow

    $sel = Read-Host ("番号を入力してください (0～{0} / カンマ区切り可 / Enterでスキップ)" -f $catMenuSorted.Count)

    if (-not [string]::IsNullOrWhiteSpace($sel)) {
        $parts = @(
            $sel.Split(",") |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -match '^\d+$' }
        )

        if ($parts.Count -gt 0) {
            $pickedGroups = @()
            $pickedLabels = @()

            foreach ($p in $parts) {
                $num = [int]$p

                if ($num -eq 0) {
                    $manual = Read-Host "Word を入力してください（複数可: 空白区切り）"
                    if (-not [string]::IsNullOrWhiteSpace($manual)) {
                        $manualWords = @(
                            $manual.Split() |
                            ForEach-Object { $_.Trim() } |
                            Where-Object { $_ -ne "" }
                        )
                        if ($manualWords.Count -gt 0) {
                            $pickedGroups += ,([string[]]$manualWords)
                            $pickedLabels += ("手入力:" + ($manualWords -join "+"))
                        }
                    }
                }
                elseif ($num -ge 1 -and $num -le $catMenuSorted.Count) {
                    $c = $catMenuSorted[$num - 1]
                    $pickedGroups += ,([string[]]$c.Tokens)
                    $pickedLabels += $c.Label
                }
            }

            if ($pickedGroups.Count -gt 0) {
                $MustContainGroups = @($pickedGroups)
                $MustContain = @()
                $Word = $null

                Write-Host ("選択されたカテゴリ: {0}" -f ($pickedLabels -join ", ")) -ForegroundColor Green
                Write-Host "抽出条件: （カテゴリ内 token AND）を（カテゴリ間 OR）" -ForegroundColor DarkGray
            }
        }
    }

    Write-Host ""
}

# ======== MustContain の最終決定 ========
if (($MustContainGroups.Count -eq 0) -and (-not $PSBoundParameters.ContainsKey('MustContain')) -and (-not $MustContain -or $MustContain.Count -eq 0)) {
    if (-not [string]::IsNullOrWhiteSpace($Word)) {
        $MustContain = @($Word)
    }
    else {
        if (-not [string]::IsNullOrWhiteSpace($Mode) -and $ModeToken.ContainsKey($Mode)) {
            $MustContain = @($ModeToken[$Mode])
        } else {
            $MustContain = @()
        }
    }
}

# ===== ログ =====
Write-Host ("=== Mode: {0} / UseModeFolder: {1} / Recurse: {2} ===" -f $Mode, $UseModeFolder.IsPresent, $Recurse.IsPresent) -ForegroundColor Cyan
Write-Host ("=== src: {0}" -f $src) -ForegroundColor DarkCyan
Write-Host ("=== trans: {0}" -f $trans) -ForegroundColor DarkCyan
Write-Host ("=== dest: {0}" -f $dest) -ForegroundColor DarkCyan
Write-Host ("=== MustNotContain: {0}" -f ($MustNotContain -join ",")) -ForegroundColor DarkGray

if ($MustContainGroups.Count -gt 0) {
    $gStr = @()
    foreach ($g in $MustContainGroups) {
        $gStr += ("(" + (($g -join "+")) + ")")
    }
    Write-Host ("=== MustContainGroups: {0}" -f ($gStr -join " OR ")) -ForegroundColor DarkGray
}
else {
    Write-Host ("=== MustContain: {0}" -f ($MustContain -join ",")) -ForegroundColor DarkGray
}

# ===== 対象フォルダのファイル数を表示 =====
$allToday = @(Get-SourceFiles -root $src -Recurse:$Recurse)
Write-Host ("=== 対象フォルダ内のファイル数: {0} 件 ===" -f $allToday.Count) -ForegroundColor Cyan

# ===== 抽出 =====
$srcFiles = @(
    $allToday | Where-Object {
        $name = $_.Name

        $matchContain = if ($MustContainGroups.Count -gt 0) {
            Matches-AnyTokenGroup -name $name -groups $MustContainGroups
        } else {
            Matches-AllTokens -name $name -tokens $MustContain
        }

        $matchContain -and (Matches-NoneTokens -name $name -tokens $MustNotContain)
    }
)

if ($srcFiles.Count -eq 0) {
    Write-Host "条件を満たすファイルがありません。" -ForegroundColor Yellow
    $swAll.Stop()
    return
}

$pickCount   = [Math]::Min($CopyCount, $srcFiles.Count)
$randomFiles = @(
    Get-Random -InputObject $srcFiles -Count $pickCount
)

Write-Host ("=== 抽出対象 {0} 件 ===" -f $pickCount) -ForegroundColor Cyan
$randomFiles | ForEach-Object {
    Write-Host ("  - " + $_.FullName) -ForegroundColor Gray
}

# ===== 類似チェック準備 =====
$doneFiles = @(
    if (Test-Path -LiteralPath $BaseToday) {
        Get-ChildItem -LiteralPath $BaseToday -File -Recurse
    } else {
        @()
    }
)

$transFiles = @(
    if (Test-Path -LiteralPath $trans) {
        Get-ChildItem -LiteralPath $trans -File -Recurse
    } else {
        @()
    }
)

$allIndex = @(
    foreach ($f in ($doneFiles + $transFiles)) {
        [PSCustomObject]@{
            Path     = $f.FullName
            Name     = $f.Name
            NormName = (Normalize-Name $f.Name)
            Source   = if ($f.FullName -like "$trans*") { "github" } else { "done" }
        }
    }
)

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

$thPct = [Math]::Round($Threshold * 100, 0)
Write-Host ("=== 類似判定しきい値: {0}% ===" -f $thPct) -ForegroundColor DarkCyan

$copied = 0
$idx = 0
$copiedFiles = @()
$similarCopied = 0
$plainCopied = 0

foreach ($srcFile in $randomFiles) {
    $idx++
    $swOne = [System.Diagnostics.Stopwatch]::StartNew()

    $srcName = $srcFile.Name
    $srcNorm = Normalize-Name $srcName

    Write-Host ("[{0}/{1}] チェック中: {2}" -f $idx, $pickCount, $srcFile.FullName) -ForegroundColor DarkCyan

    $bestSim = 0.0
    $best = $null

    $k = if ($srcNorm.Length -ge 2) { $srcNorm.Substring(0,2) } else { $srcNorm }
    $cands = @()
    if ($bucket.ContainsKey($k)) { $cands += $bucket[$k] }

    if ($cands.Count -lt 50 -and $srcNorm.Length -ge 1) {
        $k1 = $srcNorm.Substring(0,1)
        foreach ($kk in $bucket.Keys) {
            if ($kk.StartsWith($k1)) { $cands += $bucket[$kk] }
        }
    }

    if ($cands.Count -eq 0) {
        $cands = @($allIndex)
    }

    $lenA = $srcNorm.Length
    $cands = @(
        $cands | Where-Object {
            $lenB = $_.NormName.Length
            [Math]::Abs($lenA - $lenB) -le 20
        }
    )

    foreach ($d in $cands) {
        $sim = Get-NormalizedSimilarity $srcNorm $d.NormName
        if ($sim -gt $bestSim) {
            $bestSim = $sim
            $best = $d
        }
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
        if ($best -and $xorShort -and (($bestSim -ge $Threshold) -or ($simNoShort -ge $Threshold))) {
            Write-Host ("  → 'short' 片側一致：コピー（類似:{0:F1}% / 相手:{1} [{2}]）" -f ($bestSim * 100), $best.Name, $best.Source) -ForegroundColor Yellow
            Copy-Item -LiteralPath $srcFile.FullName -Destination $dest -Force -WhatIf:$WhatIf
            $copied++
            $similarCopied++
            $copiedFiles += (Join-Path $dest $srcFile.Name)
            Show-StepTime $swOne $swAll
            continue
        }

        if ($best -and $bestSim -ge $Threshold) {
            Write-Host ("  → 類似ありだがコピー: {0:F1}% / 相手:{1} [{2}]" -f ($bestSim * 100), $best.Name, $best.Source) -ForegroundColor Yellow
            Copy-Item -LiteralPath $srcFile.FullName -Destination $dest -Force -WhatIf:$WhatIf
            $copied++
            $similarCopied++
            $copiedFiles += (Join-Path $dest $srcFile.Name)
            Show-StepTime $swOne $swAll
            continue
        }

        if ($best -and $simNoShort -ge $Threshold) {
            Write-Host ("  → short除去類似ありだがコピー: {0:F1}% / 相手:{1} [{2}]" -f ($simNoShort * 100), $best.Name, $best.Source) -ForegroundColor Yellow
            Copy-Item -LiteralPath $srcFile.FullName -Destination $dest -Force -WhatIf:$WhatIf
            $copied++
            $similarCopied++
            $copiedFiles += (Join-Path $dest $srcFile.Name)
            Show-StepTime $swOne $swAll
            continue
        }

        Copy-Item -LiteralPath $srcFile.FullName -Destination $dest -Force -WhatIf:$WhatIf
        Write-Host "  → 類似ファイルなし。コピーしました。" -ForegroundColor Green
        $copied++
        $plainCopied++
        $copiedFiles += (Join-Path $dest $srcFile.Name)
        Show-StepTime $swOne $swAll
    }
    catch {
        Write-Host ("  → 処理失敗: {0}" -f $_.Exception.Message) -ForegroundColor Red
        Show-StepTime $swOne $swAll
    }
}

Write-Host ""

if ($copiedFiles.Count -gt 0) {
    Write-Host "=== コピーしたファイル一覧 ===" -ForegroundColor Green
    foreach ($p in $copiedFiles) {
        Write-Host ("  " + $p) -ForegroundColor Gray
    }
}
else {
    Write-Host "コピーされたファイルはありません。" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== サマリ ===" -ForegroundColor DarkCyan
Write-Host ("  コピー合計         : {0} 件" -f $copied) -ForegroundColor Green
Write-Host ("    類似ありコピー   : {0} 件" -f $similarCopied) -ForegroundColor Yellow
Write-Host ("    通常コピー       : {0} 件" -f $plainCopied) -ForegroundColor Green

$allSecMid = $swAll.Elapsed.TotalSeconds
$allTSMid  = [TimeSpan]::FromSeconds($allSecMid)
Write-Host ("=== 第1部 累計: {0:N1}s ({1:mm\:ss}) ===" -f $allSecMid, $allTSMid) -ForegroundColor Cyan

################## ここから txt ファイル名リネーム ##################

$ErrorActionPreference = 'Stop'

$files = @(Get-ChildItem -File -Filter *.txt)
if ($files.Count -eq 0) {
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
            $conflicted++
            $renamed++
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

$swAll.Stop()
$allSec = $swAll.Elapsed.TotalSeconds
$allTS  = [TimeSpan]::FromSeconds($allSec)
Write-Host ("総処理時間  : {0:N1}s ({1:mm\:ss})" -f $allSec, $allTS) -ForegroundColor Cyan