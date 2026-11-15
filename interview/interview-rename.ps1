
# Rename-InterviewVideos-CSV.ps1
# PowerShell 5.1 / 7
#
# 確認モード:
#   .\Rename-InterviewVideos-CSV.ps1
#
# 実行モード:
#   .\Rename-InterviewVideos-CSV.ps1 -Execute
#
# CSV形式（ヘッダーなし）:
#   タイトル,元TXTまたはMP4ファイル名
#
# 例:
#   新宿の夜,IMG_0661_vertical_01_71s_start619s.mp4
#   東京の文化,IMG_0661_vertical_02_80s_start978s.txt

param(
    [switch]$Execute
)

$ErrorActionPreference = 'Stop'

$base = (Get-Location).Path

Write-Host ""
Write-Host "=========================================="
Write-Host " インタビュー動画 CSV一括リネーム"
Write-Host "=========================================="
Write-Host "作業ディレクトリ: $base"

if ($Execute) {
    Write-Host "モード: 実行" -ForegroundColor Yellow
}
else {
    Write-Host "モード: 確認のみ" -ForegroundColor Cyan
}

# ============================================
# 1. ディレクトリ一覧表示
# ============================================

$dirs = @(
    Get-ChildItem -LiteralPath $base -Directory |
        Sort-Object Name
)

if ($dirs.Count -eq 0) {
    throw "サブディレクトリがありません: $base"
}

Write-Host ""
Write-Host "処理対象ディレクトリを選択してください。"
Write-Host ""

for ($i = 0; $i -lt $dirs.Count; $i++) {
    Write-Host ("{0,3}: {1}" -f ($i + 1), $dirs[$i].Name)
}

Write-Host ""
Write-Host "  0: キャンセル"
Write-Host ""

while ($true) {

    $inputValue = Read-Host "ディレクトリ番号"

    $selectedNumber = 0

    $valid = [int]::TryParse(
        $inputValue,
        [ref]$selectedNumber
    )

    if (-not $valid) {
        Write-Host "数字を入力してください。" -ForegroundColor Yellow
        continue
    }

    if ($selectedNumber -eq 0) {
        Write-Host "キャンセルしました。"
        return
    }

    if ($selectedNumber -ge 1 -and
        $selectedNumber -le $dirs.Count) {
        break
    }

    Write-Host "一覧にある番号を入力してください。" `
        -ForegroundColor Yellow
}

$videoDir = $dirs[$selectedNumber - 1].FullName

Write-Host ""
Write-Host "選択ディレクトリ: $videoDir" -ForegroundColor Cyan

# ============================================
# 2. Prefix入力
# ============================================

$Prefix = ""

while ($true) {

    $answer = (
        Read-Host "ファイル名の先頭に文字列を追加しますか？ (Y/N)"
    ).Trim()

    if ($answer -match '^(y|yes)$') {

        while ($true) {

            $Prefix = (
                Read-Host "追加する文字列"
            ).Trim()

            if (-not [string]::IsNullOrWhiteSpace($Prefix)) {
                break
            }

            Write-Host "空欄は指定できません。" `
                -ForegroundColor Yellow
        }

        break
    }

    if ($answer -match '^(n|no)$') {
        $Prefix = ""
        break
    }

    Write-Host "Y または N を入力してください。" `
        -ForegroundColor Yellow
}

# 禁止文字を置換
$Prefix = $Prefix -replace '[\\/:*?"<>|\x00-\x1F]', '-'

Write-Host ""
Write-Host "使用Prefix: [$Prefix]" -ForegroundColor Cyan

# ============================================
# 3. 最新CSVを自動選択
# ============================================

# 選択したディレクトリ直下を優先
$csvFiles = @(
    Get-ChildItem -LiteralPath $videoDir -File -Filter '*.csv' |
        Sort-Object LastWriteTime -Descending
)

# なければ作業ディレクトリ直下
if ($csvFiles.Count -eq 0) {

    $csvFiles = @(
        Get-ChildItem -LiteralPath $base -File -Filter '*.csv' |
            Sort-Object LastWriteTime -Descending
    )
}

# それでもなければ選択ディレクトリ以下を再帰検索
if ($csvFiles.Count -eq 0) {

    $csvFiles = @(
        Get-ChildItem -LiteralPath $videoDir `
            -Recurse -File -Filter '*.csv' |
            Sort-Object LastWriteTime -Descending
    )
}

if ($csvFiles.Count -eq 0) {
    throw "CSVが見つかりません。"
}

$CsvPath = $csvFiles[0].FullName

Write-Host "使用CSV: $CsvPath" -ForegroundColor Cyan

# ============================================
# 4. CSV読み込み
# ============================================

# 1列目: タイトル
# 2列目: TXTまたはMP4ファイル名

$rows = @(
    Import-Csv -LiteralPath $CsvPath `
        -Header 'Title','FileName' `
        -Encoding UTF8
)

if ($rows.Count -eq 0) {
    throw "CSVが空です。"
}

Write-Host "CSV行数: $($rows.Count)"

# ============================================
# 5. MP4一覧取得
# ============================================

$videos = @(
    Get-ChildItem -LiteralPath $videoDir `
        -Recurse -File -Filter '*.mp4'
)

if ($videos.Count -eq 0) {
    throw "MP4が見つかりません: $videoDir"
}

Write-Host "検出MP4数: $($videos.Count)"

# ============================================
# 6. リネーム計画作成
# ============================================

$plans = @()
$seenSources = @{}
$seenTargets = @{}
$lineNumber = 0

foreach ($row in $rows) {

    $lineNumber++

    $title = ([string]$row.Title).Trim().Trim([char]0xFEFF)
    $fileName = ([string]$row.FileName).Trim()

    if (
        [string]::IsNullOrWhiteSpace($title) -or
        [string]::IsNullOrWhiteSpace($fileName)
    ) {
        throw "CSV $lineNumber 行目に空欄があります。"
    }

    # パスが含まれる場合はファイル名だけを取り出す
    $fileName = [IO.Path]::GetFileName(
        $fileName.Replace('/', '\')
    )

    # TXTまたはMP4を許可
    $ext = [IO.Path]::GetExtension($fileName)

    if ($ext -notin @('.txt', '.mp4')) {
        throw "CSV $lineNumber 行目: TXT/MP4ファイル名ではありません: $fileName"
    }

    # 拡張子を除去し、末尾の(1)などを削除
    $stem = [IO.Path]::GetFileNameWithoutExtension($fileName) `
        -replace '\(\d+\)$', ''

    $oldVideoName = "$stem.mp4"

    # 対応MP4を検索
    $found = @(
        $videos | Where-Object {
            $_.Name -ieq $oldVideoName
        }
    )

    if ($found.Count -ne 1) {
        throw "CSV $lineNumber 行目: 対象MP4が一意に特定できません ($($found.Count)件): $oldVideoName"
    }

    $video = $found[0]

    # タイトルの禁止文字を置換
    $safeTitle = (
        $title -replace '[\\/:*?"<>|\x00-\x1F]', '-'
    ).Trim().TrimEnd('.')

    if ([string]::IsNullOrWhiteSpace($safeTitle)) {
        throw "CSV $lineNumber 行目: 使用可能なタイトルがありません。"
    }

    # Prefix + タイトル + 拡張子
    $newName = "$Prefix$safeTitle.mp4"

    # ファイル名の末尾の空白・ピリオドを除去
    $newName = (
        [IO.Path]::GetFileNameWithoutExtension($newName)
    ).TrimEnd(' ', '.') + '.mp4'

    $targetPath = Join-Path $video.DirectoryName $newName

    # 重複確認
    $sourceKey = $video.FullName.ToLowerInvariant()
    $targetKey = $targetPath.ToLowerInvariant()

    if ($seenSources.ContainsKey($sourceKey)) {
        throw "CSVの元ファイルが重複しています: $oldVideoName"
    }

    if ($seenTargets.ContainsKey($targetKey)) {
        throw "変更後のファイル名が重複しています: $newName"
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
        No         = $lineNumber
        OldName    = $video.Name
        NewName    = $newName
        SourcePath = $video.FullName
        TargetPath = $targetPath
    }
}

# ============================================
# 7. リネーム予定一覧
# ============================================

Write-Host ""
Write-Host "=========================================="
Write-Host " リネーム予定一覧"
Write-Host "=========================================="

$plans |
    Format-Table No, OldName, NewName -AutoSize -Wrap

Write-Host ""
Write-Host "選択フォルダ: $videoDir"
Write-Host "使用CSV: $CsvPath"
Write-Host "Prefix: [$Prefix]"
Write-Host "対象件数: $($plans.Count)"
Write-Host ""

# ============================================
# 8. 確認モード
# ============================================

if (-not $Execute) {

    Write-Host "確認モード: ファイル名は変更していません。" `
        -ForegroundColor Yellow

    Write-Host ""
    Write-Host "実行するには次のコマンドを使用してください。"
    Write-Host ".\Rename-InterviewVideos-CSV.ps1 -Execute" `
        -ForegroundColor Cyan

    return
}

# ============================================
# 9. 実行モードの最終確認
# ============================================

$confirm = (
    Read-Host "上記のファイル名に変更しますか？ (Y/N)"
).Trim()

if ($confirm -notmatch '^(y|yes)$') {

    Write-Host "キャンセルしました。ファイルは変更していません。" `
        -ForegroundColor Yellow

    return
}

# ============================================
# 10. リネーム実行
# ============================================

$completed = 0
$skipped = 0
$failed = 0

foreach ($item in $plans) {

    if ($item.OldName -ceq $item.NewName) {

        Write-Host "変更不要: $($item.NewName)"
        $skipped++
        continue
    }

    try {

        # 実行直前にも変更先の存在を確認
        if (
            (Test-Path -LiteralPath $item.TargetPath) -and
            ($item.SourcePath -ine $item.TargetPath)
        ) {
            throw "変更先ファイルが既に存在します。"
        }

        Rename-Item -LiteralPath $item.SourcePath `
            -NewName $item.NewName `
            -ErrorAction Stop

        $completed++

        Write-Host ("[{0}] {1} -> {2}" -f `
            $completed, $item.OldName, $item.NewName) `
            -ForegroundColor Green
    }
    catch {

        $failed++

        Write-Host "変更失敗: $($item.OldName)" `
            -ForegroundColor Red

        Write-Host $_.Exception.Message -ForegroundColor Red
    }
}

# ============================================
# 11. 結果表示
# ============================================

Write-Host ""
Write-Host "=========================================="
Write-Host " 処理結果"
Write-Host "=========================================="

Write-Host "選択フォルダ: $videoDir"
Write-Host "使用CSV: $CsvPath"
Write-Host "Prefix: [$Prefix]"
Write-Host "対象件数: $($plans.Count)"
Write-Host "変更成功: $completed"
Write-Host "変更不要: $skipped"
Write-Host "変更失敗: $failed"

if ($failed -eq 0) {
    Write-Host "処理が完了しました。" -ForegroundColor Green
}
else {
    Write-Host "一部のリネームに失敗しました。" `
        -ForegroundColor Yellow
}
