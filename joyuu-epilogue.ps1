param(
    [Parameter(Mandatory = $true)]
    [string]$SetupScriptPath,

    [Parameter(Mandatory = $true)]
    [string]$TextFilePath
)

# ============================================================
# 実行時間計測（必ず最後に表示：途中で落ちても出る）
# ============================================================
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$startedAt = Get-Date

try {

    Write-Host "=== Short Runner (Auto Video) ==="
    Write-Host "Setup Script: $SetupScriptPath"
    Write-Host "Text File: $TextFilePath"
    Write-Host ""

    # ===== 入力ファイル名の正規化＆リネーム =====
    function Normalize-AndRename([string]$path) {
        $dir   = Split-Path -Parent $path
        $leaf  = Split-Path -Leaf   $path

        # 1) 互換正規化（全角英数/記号→半角など）
        $normLeaf = $leaf.Normalize([System.Text.NormalizationForm]::FormKC)

        # 2) 拡張子とベース名に分割
        $ext  = [IO.Path]::GetExtension($normLeaf)
        $base = [IO.Path]::GetFileNameWithoutExtension($normLeaf)

        # 3) 空白（半角/全角）→ _
        $base = $base -replace '[\s\u3000]+', '_'

        # 4) Windows 禁止文字 → _
        #    <>:"/\|?* はもちろん、制御文字も除去
        $base = $base -replace '[<>:"/\\|?*\x00-\x1F]', '_'

        # 5) 記号のうち、ドット・ハイフン・アンダースコア以外は _
        #    ただし日本語等の文字(\p{L})と数字(\p{N})は許可
        $base = $base -replace '[^\p{L}\p{N}\._-]', '_'

        # 6) 連続する _ を1つに、先頭末尾の _ をトリム
        $base = ($base -replace '_{2,}', '_').Trim('_')

        # 空になってしまった場合のフォールバック
        if ([string]::IsNullOrWhiteSpace($base)) { $base = 'file' }

        $newLeaf = "$base$ext"
        $oldFull = Join-Path $dir $leaf
        $newFull = Join-Path $dir $newLeaf

        # 実ファイルが存在し、名前が変わるならリネーム
        if ((Test-Path -LiteralPath $oldFull) -and ($oldFull -ne $newFull)) {
            try {
                Move-Item -LiteralPath $oldFull -Destination $newFull -Force
                Write-Host "? リネーム: $oldFull → $newFull"
            } catch {
                Write-Warning "?? リネーム失敗: $oldFull → $newFull : $($_.Exception.Message)"
                # 失敗時は旧名を返す
                return $oldFull
            }
        }

        return $newFull
    }

    $SetupScriptPath = Normalize-AndRename $SetupScriptPath
    $TextFilePath    = Normalize-AndRename $TextFilePath

    Write-Host "正規化後のSetup Script: $SetupScriptPath"
    Write-Host "正規化後のText File:   $TextFilePath"
    Write-Host ""

    # ===== 背景動画を自動推定 =====
    $setupName = [IO.Path]::GetFileNameWithoutExtension($SetupScriptPath)
    $baseMatch = $setupName -replace '^\d+-', '' -replace '-x$', ''
    $backgroundVideo = "..\..\ecobiz-images\$($baseMatch)_3x.mp4"

    Write-Host "推定された背景動画: $backgroundVideo"
    Write-Host ""

    # ===== 下準備スクリプト実行 =====
    if (Test-Path -LiteralPath $SetupScriptPath) {
        Write-Host "[1/3] 実行中: $SetupScriptPath ..."
        & $SetupScriptPath
        Write-Host "[1/3] 完了。"
    } else {
        throw "エラー: $SetupScriptPath が見つかりません。"
    }

    # ===== ショート版＋エピローグ生成 =====
    if ((Test-Path -LiteralPath $TextFilePath) -and (Test-Path -LiteralPath $backgroundVideo)) {
        Write-Host "[2/3] 実行中: run-joyuu-epilogue.ps1 ..."
        & .\run-joyuu-epilogue.ps1 $TextFilePath $backgroundVideo
        Write-Host "[2/3] 完了。"
    } else {
        throw "エラー: テキストまたは動画が見つかりません。確認: $TextFilePath, $backgroundVideo"
    }

    Write-Host "=== すべて完了しました ==="

}
finally {
    $sw.Stop()
    $endedAt = Get-Date

    Write-Host ""
    Write-Host "=============================="
    Write-Host ("開始: {0:yyyy-MM-dd HH:mm:ss}" -f $startedAt)
    Write-Host ("終了: {0:yyyy-MM-dd HH:mm:ss}" -f $endedAt)
    Write-Host ("実行時間: {0:hh\:mm\:ss\.fff}" -f $sw.Elapsed)
    Write-Host "=============================="
}
