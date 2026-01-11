Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ===== 設定 =====
$sourceRoot      = "D:\"
$imagesDir       = "D:\ecobiz-youtube-uploader\google-trans\images"
$backupMainDir   = "D:\ecobiz-images"
$backupSubDir    = "D:\ecobiz-images\backup"

# 古いファイル削除の閾値（LastWriteTime ??）
$cutoffImages    = (Get-Date).AddDays(-1)   # images は 1日より古いのは消す
$cutoffRoot      = (Get-Date).AddDays(-2)   # D:\直下は 2日より古いのは消す
$cutoffBackup    = (Get-Date).AddDays(0)    # ecobiz-images は 0日… ←危険なので「消さない」に変更（必要なら下で有効化）

# ===== 事前作成 =====
foreach ($d in @($imagesDir, $backupMainDir, $backupSubDir)) {
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d | Out-Null }
}

function Remove-OldMp4([string]$dir, [datetime]$cutoff) {
    Get-ChildItem -LiteralPath $dir -Filter "*.mp4" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoff } |
        ForEach-Object {
            try {
                Remove-Item -LiteralPath $_.FullName -Force
                Write-Host "削除: $($_.FullName)"
            } catch {
                Write-Warning "削除失敗: $($_.FullName) - $($_.Exception.Message)"
            }
        }
}

# ===== 古いmp4の削除（安全寄り） =====
Remove-OldMp4 -dir $imagesDir -cutoff $cutoffImages
Remove-OldMp4 -dir $sourceRoot -cutoff $cutoffRoot

# ※ ecobiz-images 側の「当日以外全消し」は危険なので、必要な時だけ有効化してください
# Remove-OldMp4 -dir $backupMainDir -cutoff $cutoffBackup

# ===== D:\直下のmp4を images へ移動 =====
Get-ChildItem -LiteralPath $sourceRoot -Filter "*.mp4" -File -ErrorAction SilentlyContinue |
    ForEach-Object {
        $src = $_.FullName
        $dst = Join-Path $imagesDir $_.Name
        try {
            Move-Item -LiteralPath $src -Destination $dst -Force
            Write-Host "移動: $src -> $dst"
        } catch {
            Write-Warning "移動失敗: $src - $($_.Exception.Message)"
        }
    }

# ===== _3x を含まないmp4を concat して _3x を作る =====
$toConvert = Get-ChildItem -LiteralPath $imagesDir -Filter "*.mp4" -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notlike "*_3x*" -and $_.Name -notlike "*temp*" }

foreach ($f in $toConvert) {
    $inPath   = $f.FullName
    $baseName = [IO.Path]::GetFileNameWithoutExtension($f.Name)
    $outName  = "${baseName}_3x$($f.Extension)"
    $outPath  = Join-Path $imagesDir $outName

    Write-Host "処理開始: $inPath"
    try {
        # concat-3x.ps1 が「カレントに出す」前提なら、ここで作業ディレクトリを images に固定するのが安全
        Push-Location $imagesDir
        try {
            # 変換
            .\concat-3x.ps1 $inPath
        } finally {
            Pop-Location
        }

        # 出力ファイルは imagesDir にあるはず、という前提で限定的に探す（再帰しない）
        $found = Get-ChildItem -LiteralPath $imagesDir -Filter $outName -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $found) {
            Write-Warning "出力ファイルが見つかりません: $outName（concat-3x.ps1 の出力先を確認）"
            continue
        }

        # 既に imagesDir にあるなら Move不要だが、保険で強制配置
        if ($found.FullName -ne $outPath) {
            Move-Item -LiteralPath $found.FullName -Destination $outPath -Force
        }
        Write-Host "出力確認: $outPath"

        # 元ファイル削除
        Remove-Item -LiteralPath $inPath -Force
        Write-Host "削除完了: $inPath"
    }
    catch {
        Write-Warning "エラー: $($f.Name) - $($_.Exception.Message)"
    }
}

# ===== 10- をファイル名から削除（NewName は“名前”だけ渡す） =====
Get-ChildItem -LiteralPath $imagesDir -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like "10-*" } |
    ForEach-Object {
        $newLeaf = ($_.Name -replace "^10-", "")
        try {
            Rename-Item -LiteralPath $_.FullName -NewName $newLeaf -Force
            Write-Host "ファイル名変更: $($_.Name) -> $newLeaf"
        } catch {
            Write-Warning "リネーム失敗: $($_.Name) - $($_.Exception.Message)"
        }
    }

# ===== temp系削除（imagesDir のみに限定して誤爆防止） =====
Get-ChildItem -LiteralPath $imagesDir -Filter "*temp*.mp4" -File -ErrorAction SilentlyContinue |
    ForEach-Object {
        try {
            Remove-Item -LiteralPath $_.FullName -Force
            Write-Host "削除: $($_.FullName)"
        } catch {
            Write-Warning "削除失敗: $($_.FullName) - $($_.Exception.Message)"
        }
    }

# ===== バックアップコピー（temp除外） =====
Get-ChildItem -LiteralPath $imagesDir -Filter "*.mp4" -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notlike "*temp*" } |
    ForEach-Object {
        foreach ($bdir in @($backupMainDir, $backupSubDir)) {
            $dst = Join-Path $bdir $_.Name
            try {
                Copy-Item -LiteralPath $_.FullName -Destination $dst -Force
                Write-Host "バックアップ: $($_.FullName) -> $dst"
            } catch {
                Write-Warning "バックアップ失敗: $($_.FullName) -> $dst - $($_.Exception.Message)"
            }
        }
    }

# 最後に imagesDir に移動（必要なら）
Set-Location $imagesDir
