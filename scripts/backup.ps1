# ============================================================
# 複数フォルダ バックアップスクリプト
#
# 機能
# - 3フォルダをEドライブへ日時付きでバックアップ
# - robocopyを使用
# - ログファイル保存
# - コピー元が無い場合はスキップ
# - Robocopy終了コード判定
# - 各ジョブの処理時間表示
# - 各ジョブ終了時に累積時間表示
# - 最後に総処理時間表示
# - 24時間を超えた場合は「○日 HH:MM:SS」で表示
# ============================================================


# ------------------------------------------------------------
# 経過時間を文字列に変換する関数
# ------------------------------------------------------------
function Format-ElapsedTime {
    param (
        [TimeSpan]$TimeSpan
    )

    if ($TimeSpan.Days -gt 0) {
        return "{0}日 {1:00}:{2:00}:{3:00}" -f `
            $TimeSpan.Days,
            $TimeSpan.Hours,
            $TimeSpan.Minutes,
            $TimeSpan.Seconds
    }
    else {
        return "{0:00}:{1:00}:{2:00}" -f `
            $TimeSpan.Hours,
            $TimeSpan.Minutes,
            $TimeSpan.Seconds
    }
}


# ------------------------------------------------------------
# 全体処理開始時刻
# ------------------------------------------------------------
$overallStart = Get-Date


# ------------------------------------------------------------
# バックアップ用タイムスタンプ
# ------------------------------------------------------------
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"


# ------------------------------------------------------------
# ログファイル
# ------------------------------------------------------------
$logFile = "E:\backup-log-$timestamp.txt"


# ------------------------------------------------------------
# バックアップ対象
# ------------------------------------------------------------
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


# ------------------------------------------------------------
# 集計用変数
# ------------------------------------------------------------
$successCount = 0
$failureCount = 0
$skipCount = 0

$totalJobs = $backupJobs.Count
$currentJob = 0


# ------------------------------------------------------------
# 開始メッセージ
# ------------------------------------------------------------
Write-Host ""
Write-Host "============================================================"
Write-Host "バックアップ処理を開始します。"
Write-Host "============================================================"
Write-Host "開始時刻 : $($overallStart.ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Host "対象件数 : $totalJobs 件"
Write-Host "ログ     : $logFile"
Write-Host "============================================================"


# ------------------------------------------------------------
# バックアップループ
# ------------------------------------------------------------
foreach ($job in $backupJobs) {

    $currentJob++

    $jobStart = Get-Date

    $source = $job.Source
    $destination = $job.Destination

    $elapsedBefore = (Get-Date) - $overallStart


    # --------------------------------------------------------
    # ジョブ開始表示
    # --------------------------------------------------------
    Write-Host ""
    Write-Host "============================================================"
    Write-Host "バックアップ開始 [$currentJob / $totalJobs]"
    Write-Host "============================================================"
    Write-Host "開始時刻         : $($jobStart.ToString('yyyy-MM-dd HH:mm:ss'))"
    Write-Host "コピー元         : $source"
    Write-Host "コピー先         : $destination"
    Write-Host "ログ             : $logFile"
    Write-Host "開始時累積時間   : $(Format-ElapsedTime $elapsedBefore)"
    Write-Host "============================================================"


    # --------------------------------------------------------
    # コピー元の存在確認
    # --------------------------------------------------------
    if (-not (Test-Path -LiteralPath $source)) {

        Write-Warning "コピー元が見つからないためスキップします。"
        Write-Warning "コピー元: $source"

        $skipCount++

        $jobEnd = Get-Date
        $jobElapsed = $jobEnd - $jobStart
        $totalElapsed = $jobEnd - $overallStart

        Write-Host ""
        Write-Host "------------------------------------------------------------"
        Write-Host "結果       : スキップ"
        Write-Host "終了時刻   : $($jobEnd.ToString('yyyy-MM-dd HH:mm:ss'))"
        Write-Host "処理時間   : $(Format-ElapsedTime $jobElapsed)"
        Write-Host "累積時間   : $(Format-ElapsedTime $totalElapsed)"
        Write-Host "------------------------------------------------------------"

        continue
    }


    # --------------------------------------------------------
    # robocopy実行
    # --------------------------------------------------------
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


    # --------------------------------------------------------
    # robocopy終了コード
    # --------------------------------------------------------
    $exitCode = $LASTEXITCODE


    # --------------------------------------------------------
    # ジョブ終了時刻・時間
    # --------------------------------------------------------
    $jobEnd = Get-Date
    $jobElapsed = $jobEnd - $jobStart
    $totalElapsed = $jobEnd - $overallStart


    # --------------------------------------------------------
    # 結果表示
    # --------------------------------------------------------
    Write-Host ""
    Write-Host "------------------------------------------------------------"
    Write-Host "バックアップ結果 [$currentJob / $totalJobs]"
    Write-Host "------------------------------------------------------------"
    Write-Host "終了時刻   : $($jobEnd.ToString('yyyy-MM-dd HH:mm:ss'))"
    Write-Host "処理時間   : $(Format-ElapsedTime $jobElapsed)"
    Write-Host "累積時間   : $(Format-ElapsedTime $totalElapsed)"
    Write-Host "終了コード : $exitCode"


    # --------------------------------------------------------
    # Robocopy終了コード判定
    #
    # 0 : コピー不要
    # 1 : 正常コピー
    # 2～7 : 差分や警告はあるが処理成功扱い
    # 8以上 : エラー
    # --------------------------------------------------------
    if ($exitCode -le 7) {

        Write-Host "状態       : 成功"
        Write-Host "コピー先   : $destination"

        $successCount++
    }
    else {

        Write-Error "状態       : 失敗"
        Write-Error "コピー元   : $source"

        $failureCount++
    }

    Write-Host "------------------------------------------------------------"
}


# ------------------------------------------------------------
# 全バックアップ終了
# ------------------------------------------------------------
$overallEnd = Get-Date
$totalElapsed = $overallEnd - $overallStart


# ------------------------------------------------------------
# 最終集計表示
# ------------------------------------------------------------
Write-Host ""
Write-Host ""
Write-Host "============================================================"
Write-Host "すべてのバックアップ処理が終了しました。"
Write-Host "============================================================"
Write-Host ""
Write-Host "開始時刻   : $($overallStart.ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Host "終了時刻   : $($overallEnd.ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Host ""
Write-Host "総処理時間 : $(Format-ElapsedTime $totalElapsed)"
Write-Host ""
Write-Host "成功       : $successCount 件"
Write-Host "失敗       : $failureCount 件"
Write-Host "スキップ   : $skipCount 件"
Write-Host "総対象件数 : $totalJobs 件"
Write-Host ""
Write-Host "ログ       : $logFile"
Write-Host ""
Write-Host "============================================================"


# ------------------------------------------------------------
# 最終ステータス
# ------------------------------------------------------------
if ($failureCount -eq 0) {

    Write-Host "バックアップ処理は正常に終了しました。"

}
else {

    Write-Warning "$failureCount 件のバックアップでエラーが発生しました。"

}

Write-Host "============================================================"