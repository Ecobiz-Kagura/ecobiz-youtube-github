
param(
    [switch]$Execute,
    [switch]$Recurse
)

$ErrorActionPreference = "Stop"

# カレントディレクトリ
$CurrentDir = (Get-Location).Path

Write-Host "======================================"
Write-Host " URL Encoded Filename Decoder"
Write-Host "======================================"
Write-Host "対象: $CurrentDir"
Write-Host "再帰検索: $Recurse"
Write-Host "実行モード: $Execute"
Write-Host ""

# ファイル一覧
$Files = @(
    Get-ChildItem `
        -LiteralPath $CurrentDir `
        -File `
        -Recurse:$Recurse |
    Where-Object {
        $_.Name -match '%[0-9A-Fa-f]{2}'
    }
)

Write-Host "対象ファイル数: $($Files.Count)"
Write-Host ""

$Renamed = 0
$Skipped = 0
$Failed = 0

foreach ($File in $Files) {

    $OldName = $File.Name

    try {
        # URLエンコードをデコード
        # + は半角スペースに変換しない
        $NewName = [System.Uri]::UnescapeDataString($OldName)

        if ($OldName -eq $NewName) {
            $Skipped++
            continue
        }

        # Windowsで使えない文字を確認
        $InvalidChars = [System.IO.Path]::GetInvalidFileNameChars()

        if ($NewName.IndexOfAny($InvalidChars) -ge 0) {
            Write-Host "無効な文字を含むためスキップ: $NewName"
            $Skipped++
            continue
        }

        $NewPath = Join-Path $File.DirectoryName $NewName

        Write-Host "--------------------------------------"
        Write-Host "変更前: $OldName"
        Write-Host "変更後: $NewName"

        # 同名ファイルが存在する場合
        if (Test-Path -LiteralPath $NewPath) {
            Write-Host "スキップ: 変更後の名前が既に存在します"
            $Skipped++
            continue
        }

        if ($Execute) {

            Rename-Item `
                -LiteralPath $File.FullName `
                -NewName $NewName `
                -ErrorAction Stop

            Write-Host "結果: 変更完了"
            $Renamed++
        }
        else {
            Write-Host "結果: プレビューのみ"
        }
    }
    catch {
        Write-Host "エラー: $($_.Exception.Message)"
        $Failed++
    }
}

Write-Host ""
Write-Host "======================================"
Write-Host "処理結果"
Write-Host "======================================"

if ($Execute) {
    Write-Host "変更完了: $Renamed"
}
else {
    Write-Host "確認モード: ファイルは変更していません"
}

Write-Host "スキップ: $Skipped"
Write-Host "エラー: $Failed"
