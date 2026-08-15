rm D:\ecobiz-youtube-uploader\google-trans\images\*.mp4

# 移動元と移動先のパスを指定
$sourceDir = "D:\"
$destinationDir = "D:\ecobiz-youtube-uploader\google-trans\images"

#### 2025-09-19 

# 対象ディレクトリ1
$targetDir = "D:\ecobiz-youtube-uploader\google-trans\images"

# 基準日（1日前）
$cutoffDate = (Get-Date).AddDays(-1)

# 1日前より前に作成された .mp4 ファイルを削除
Get-ChildItem -Path $targetDir -Filter "*.mp4" -File | Where-Object {
    $_.CreationTime -lt $cutoffDate
} | ForEach-Object {
    Remove-Item $_.FullName -Force
    Write-Host "削除: $($_.FullName)"
}


# 対象ディレクトリ2
$targetDir = "D:\"

# 基準日（2日前）
$cutoffDate = (Get-Date).AddDays(-2)

# 2日前より前に作成された .mp4 ファイルを削除
Get-ChildItem -Path $targetDir -Filter "*.mp4" -File | Where-Object {
    $_.CreationTime -lt $cutoffDate
} | ForEach-Object {
    Remove-Item $_.FullName -Force
    Write-Host "削除: $($_.FullName)"
}


# 対象ディレクトリ3
$targetDir = "D:\ecobiz-images"

# 基準日（0日前）
$cutoffDate = (Get-Date).AddDays(-0)

# 0日前より前に作成された .mp4 ファイルを削除
Get-ChildItem -Path $targetDir -Filter "*.mp4" -File | Where-Object {
    $_.CreationTime -lt $cutoffDate
} | ForEach-Object {
    Remove-Item $_.FullName -Force
    Write-Host "削除: $($_.FullName)"
}

#######################


# 移動先フォルダが存在しない場合は作成
if (-not (Test-Path $destinationDir)) {
    New-Item -ItemType Directory -Path $destinationDir | Out-Null
}

# D:\直下の .mp4 ファイルをすべて移動
Get-ChildItem -Path $sourceDir -Filter "*.mp4" | ForEach-Object {
    $sourceFile = $_.FullName
    $targetFile = Join-Path $destinationDir $_.Name
    Move-Item -Path $sourceFile -Destination $targetFile -Force
    Write-Host "? 移動: $sourceFile → $targetFile"
}

# 過去2日以内に作成された .mp4 ファイルも対象として移動（追加取得）
$cutoffDate = (Get-Date).AddDays(-1)
Get-ChildItem -Path "D:\" -Filter "*.mp4" -File | Where-Object {
    $_.CreationTime -gt $cutoffDate
} | ForEach-Object {
    $sourceFile = $_.FullName
    $targetFile = Join-Path $destinationDir $_.Name
    try {
        Move-Item -Path $sourceFile -Destination $targetFile -Force
        Write-Host "? 移動: $sourceFile → $targetFile"
    }
    catch {
        Write-Warning "? エラー: $($_.Exception.Message)"
    }
}

# "_3x" を含まない .mp4 ファイルの一覧を取得
$videoFiles = Get-ChildItem -Path $destinationDir -Filter "*.mp4" | Where-Object {
    $_.Name -notlike "*_3x*"
}

# 各ファイルに対して concat-3x.ps1 を実行し、出力ファイルを移動＆元ファイル削除
foreach ($file in $videoFiles) {
    $filePath = $file.FullName
    Write-Host "? 処理開始: $filePath"

    try {
        # 変換スクリプト実行
        .\images\concat-3x.ps1 $filePath

        # 出力ファイル名生成
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        $ext = $file.Extension


        #$outputFileName = "${baseName}_4x$ext"
	$outputFileName = "${baseName}_3x$ext"


        $destinationPath = Join-Path $destinationDir $outputFileName

        # 出力ファイルを動的に検索（どこに出ても拾えるように）
        $outputFilePath = Get-ChildItem -Path "." -Filter $outputFileName -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1

        if ($outputFilePath) {
            Move-Item -Path $outputFilePath.FullName -Destination $destinationPath -Force
            Write-Host "? 出力ファイルを移動: $destinationPath"
        } else {
            Write-Warning "? 出力ファイルが見つかりません: $outputFileName"
        }

        # 元ファイルを削除
        Remove-Item -Path $filePath -Force
        Write-Host "? 削除完了: $filePath"
    }
    catch {
        Write-Warning "? エラー発生: $($_.Exception.Message)"
    }
}

# "10-" をファイル名から削除
Get-ChildItem -Path $destinationDir -File | Where-Object { $_.Name -like "10-*" } | ForEach-Object {
    $oldName = $_.FullName
    $newName = Join-Path $_.DirectoryName ($_.Name -replace "^10-", "")
    try {
        Rename-Item -Path $oldName -NewName $newName -Force
        Write-Host "? ファイル名変更: $($_.Name) → $(Split-Path $newName -Leaf)"
    } catch {
        Write-Warning "? リネーム失敗: $($_.Name) - $($_.Exception.Message)"
    }
}


# "11-" をファイル名から削除
Get-ChildItem -Path $destinationDir -File | Where-Object { $_.Name -like "11-*" } | ForEach-Object {
    $oldName = $_.FullName
    $newName = Join-Path $_.DirectoryName ($_.Name -replace "^11-", "")
    try {
        Rename-Item -Path $oldName -NewName $newName -Force
        Write-Host "? ファイル名変更: $($_.Name) → $(Split-Path $newName -Leaf)"
    } catch {
        Write-Warning "? リネーム失敗: $($_.Name) - $($_.Exception.Message)"
    }
}


rm *temp*.mp4

# バックアップフォルダのパスを指定
$backupDir = "D:\ecobiz-images"

# バックアップフォルダが存在しない場合は作成
if (-not (Test-Path $backupDir)) {
    New-Item -ItemType Directory -Path $backupDir | Out-Null
}

# .mp4 ファイルをすべてバックアップフォルダにコピー
#Get-ChildItem -Path $destinationDir -Filter "*.mp4" | ForEach-Object {
Get-ChildItem -Path $destinationDir -Filter "*.mp4" |
    Where-Object { $_.Name -notlike "*temp*" } |
    ForEach-Object {

    $backupPath = Join-Path $backupDir $_.Name
    try {
        Copy-Item -Path $_.FullName -Destination $backupPath -Force
        Write-Host "? バックアップ: $($_.FullName) → $backupPath"
    } catch {
        Write-Warning "?? バックアップ失敗: $($_.FullName) - $($_.Exception.Message)"
    }
}


# バックアップフォルダのパスを指定
$backupDir = "D:\ecobiz-images\backup"

# バックアップフォルダが存在しない場合は作成
if (-not (Test-Path $backupDir)) {
    New-Item -ItemType Directory -Path $backupDir | Out-Null
}

# .mp4 ファイルをすべてバックアップフォルダにコピー
#Get-ChildItem -Path $destinationDir -Filter "*.mp4" | ForEach-Object {
#    $backupPath = Join-Path $backupDir $_.Name
#    try {
#        Copy-Item -Path $_.FullName -Destination $backupPath -Force
#        Write-Host "? バックアップ: $($_.FullName) → $backupPath"
#    } catch {
#        Write-Warning "?? バックアップ失敗: $($_.FullName) - $($_.Exception.Message)"
#    }
#}

cd 