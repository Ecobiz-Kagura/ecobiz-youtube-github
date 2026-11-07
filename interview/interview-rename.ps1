
# Rename-InterviewVideos-CSV.ps1
# PowerShell 5.1 / 7
#
# 確認:
# .\Rename-InterviewVideos-CSV.ps1
#
# 実行:
# .\Rename-InterviewVideos-CSV.ps1 -Execute

param(
    [string]$CsvPath,
    [switch]$Execute
)

$ErrorActionPreference = 'Stop'

$base = (Get-Location).Path
$videoDir = Join-Path $base 'vertical_random_clips'

# 動画フォルダ確認
if (-not (Test-Path -LiteralPath $videoDir -PathType Container)) {
    throw "動画フォルダが見つかりません: $videoDir"
}

# 最新CSVを自動選択
if ([string]::IsNullOrWhiteSpace($CsvPath)) {

    $csv = Get-ChildItem -LiteralPath $base -File -Filter '*.csv' |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($null -eq $csv) {
        throw "CSVが見つかりません: $base"
    }

    $CsvPath = $csv.FullName
}

$CsvPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($CsvPath)

if (-not (Test-Path -LiteralPath $CsvPath -PathType Leaf)) {
    throw "CSVが見つかりません: $CsvPath"
}

# ヘッダーなしCSV
# 1列目: タイトル
# 2列目: 元TXTファイル名

$rows = @(
    Import-Csv -LiteralPath $CsvPath `
        -Header 'Title','FileName' -Encoding UTF8
)

if ($rows.Count -eq 0) {
    throw "CSVが空です。"
}

# MP4動画一覧
$videos = @(
    Get-ChildItem -LiteralPath $videoDir `
        -Recurse -File -Filter '*.mp4'
)

$plans = @()
$seenSources = @{}
$seenTargets = @{}
$lineNumber = 0

foreach ($row in $rows) {

    $lineNumber++

    $title = ([string]$row.Title).Trim().Trim([char]0xFEFF)
    $txtName = ([string]$row.FileName).Trim()

    if (
        [string]::IsNullOrWhiteSpace($title) -or
        [string]::IsNullOrWhiteSpace($txtName)
    ) {
        throw "CSV $lineNumber 行目に空欄があります。"
    }

    # TXTファイル名を取り出す
    $txtName = [IO.Path]::GetFileName(
        $txtName.Replace('/', '\')
    )

    if ([IO.Path]::GetExtension($txtName) -ine '.txt') {
        throw "TXTファイル名ではありません: $txtName"
    }

    # 例:
    # interview_vertical_01_283s_start1259s(1).txt
    # -> interview_vertical_01_283s_start1259s.mp4

    $stem = [IO.Path]::GetFileNameWithoutExtension($txtName) `
        -replace '\(\d+\)$', ''

    $oldVideoName = "$stem.mp4"

    # 対象MP4を検索
    $found = @(
        $videos | Where-Object {
            $_.Name -ieq $oldVideoName
        }
    )

    if ($found.Count -ne 1) {
        throw "CSV $lineNumber 行目: 対象MP4が1件に特定できません ($($found.Count)件): $oldVideoName"
    }

    $video = $found[0]

    # Windowsで使えない文字を置換
    $safeTitle = (
        $title -replace '[\\/:*?"<>|\x00-\x1F]', '-'
    ).Trim().TrimEnd('.')

    if ([string]::IsNullOrWhiteSpace($safeTitle)) {
        throw "使用可能なタイトルがありません: $title"
    }

    # 番号なしでタイトルのみ使用
    $newName = "$safeTitle.mp4"

    $targetPath = Join-Path $video.DirectoryName $newName

    # 重複チェック
    $sourceKey = $video.FullName.ToLowerInvariant()
    $targetKey = $targetPath.ToLowerInvariant()

    if ($seenSources.ContainsKey($sourceKey)) {
        throw "CSVの元ファイルが重複: $oldVideoName"
    }

    if ($seenTargets.ContainsKey($targetKey)) {
        throw "変更後のファイル名が重複: $newName"
    }

    $seenSources[$sourceKey] = $true
    $seenTargets[$targetKey] = $true

    if (
        (Test-Path -LiteralPath $targetPath) -and
        ($sourceKey -ne $targetKey)
    ) {
        throw "変更先ファイルが既に存在します: $targetPath"
    }

    $plans += [pscustomobject]@{
        OldName = $video.Name
        NewName = $newName
        Path    = $video.FullName
    }
}

# 変更予定を表示
Write-Host ""
Write-Host "使用CSV: $CsvPath"
Write-Host "動画フォルダ: $videoDir"
Write-Host "対象件数: $($plans.Count)"
Write-Host ""

$plans | Format-Table OldName, NewName -AutoSize -Wrap

# 確認モード
if (-not $Execute) {

    Write-Host "確認モード: まだ変更していません。" `
        -ForegroundColor Yellow

    Write-Host "実行するには -Execute を付けてください。"

    return
}

# リネーム実行
$completed = 0

foreach ($item in $plans) {

    if ($item.OldName -ieq $item.NewName) {
        Write-Host "変更不要: $($item.NewName)"
        continue
    }

    Rename-Item -LiteralPath $item.Path `
        -NewName $item.NewName `
        -ErrorAction Stop

    $completed++

    Write-Host "変更完了: $($item.OldName) -> $($item.NewName)"
}

Write-Host ""
Write-Host "完了: $completed 件をリネームしました。" `
    -ForegroundColor Green
