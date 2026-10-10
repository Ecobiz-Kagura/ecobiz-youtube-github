$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logFile = "E:\backup-log-$timestamp.txt"

$backupJobs = @(
    @{
        Source      = "D:\images_for_slide_show"
        Destination = "E:\backup-images_for_slide_show-$timestamp"
    },
    @{
        Source      = "D:\ecobiz-youtube-github"
        Destination = "E:\backup-ecobiz-youtube-github-$timestamp"
    },
    @{
        Source      = "D:\ecobiz-youtube-uploader"
        Destination = "E:\backup-ecobiz-youtube-uploader-$timestamp"
    }
)

$successCount = 0
$failureCount = 0
$skipCount = 0

foreach ($job in $backupJobs) {
    $source = $job.Source
    $destination = $job.Destination

    Write-Host ""
    Write-Host "========================================"
    Write-Host "バックアップ開始"
    Write-Host "開始時刻 : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Host "コピー元 : $source"
    Write-Host "コピー先 : $destination"
    Write-Host "ログ     : $logFile"
    Write-Host "========================================"

    if (-not (Test-Path -LiteralPath $source)) {
        Write-Warning "コピー元が見つからないためスキップします: $source"
        $skipCount++
        continue
    }

    robocopy `
        $source `
        $destination `
        /E `
        /COPY:DAT `
        /DCOPY:DAT `
        /R:2 `
        /W:2 `
        /V `
        /FP `
        /TS `
        /ETA `
        /TEE `
        /LOG+:$logFile

    $exitCode = $LASTEXITCODE

    Write-Host ""
    Write-Host "終了時刻   : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Host "終了コード : $exitCode"

    if ($exitCode -le 7) {
        Write-Host "バックアップ完了: $destination"
        $successCount++
    }
    else {
        Write-Error "バックアップ失敗: $source"
        $failureCount++
    }
}

Write-Host ""
Write-Host "========================================"
Write-Host "すべてのバックアップ処理が終了しました。"
Write-Host "成功     : $successCount 件"
Write-Host "失敗     : $failureCount 件"
Write-Host "スキップ : $skipCount 件"
Write-Host "ログ     : $logFile"
Write-Host "終了時刻 : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "========================================"