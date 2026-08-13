param(
    [Parameter(Mandatory = $true)]
    [string]$BackgroundVideoPath,  # 背景動画 (例: A.mp4)

    [Parameter(Mandatory = $true)]
    [string]$OverlayVideoPath,     # オーバーレイ動画

    [int]$Margin = 10,             # 左上マージン(px)
    [double]$OverlayAlpha = 0.6    # 透過度（1.0=不透明）
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# === 入力チェック（存在確認） ===
if (-not (Test-Path -LiteralPath $BackgroundVideoPath)) {
    Write-Error "背景動画が見つかりません: $BackgroundVideoPath"
    exit 1
}
if (-not (Test-Path -LiteralPath $OverlayVideoPath)) {
    Write-Error "オーバーレイ動画が見つかりません: $OverlayVideoPath"
    exit 1
}
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    Write-Error "ffmpeg が見つかりません"
    exit 1
}

# === フルパスに正規化 ===
$bgFull = (Resolve-Path -LiteralPath $BackgroundVideoPath).Path
$ovlFull = (Resolve-Path -LiteralPath $OverlayVideoPath).Path

# === 出力ファイル名（仮） ===
#   ChangeExtension($null) だと末尾にドットが付くので使わない。
#   ディレクトリ＋ベース名から安全に組み立てる。
$bgDir  = Split-Path -Parent $bgFull
$bgBase = [System.IO.Path]::GetFileNameWithoutExtension($bgFull)
$out    = Join-Path $bgDir ($bgBase + "_overlaySquare50.mp4")

# === filter_complex ===
# 横幅 = 背景の 30% → 高さも同じ → 正方形に変形（元のロジックを維持）
$filter = "[1:v][0:v]scale2ref=w=main_w*0.3:h=main_w*0.3[ovl][base];" +
          "[ovl]format=yuva420p,colorchannelmixer=aa=${OverlayAlpha}[ovla];" +
          "[base][ovla]overlay=${Margin}:${Margin}:format=auto[vout]"

Write-Host "=== overlay3-topleft.ps1 ==="
Write-Host "  Background: $bgFull"
Write-Host "  Overlay   : $ovlFull"
Write-Host "  Output    : $out"
Write-Host ""

# === ffmpeg 実行 ===
$ffArgs = @(
    "-y",
    "-i", $bgFull,
    "-stream_loop", "-1", "-i", $ovlFull,
    "-filter_complex", $filter,
    "-map", "[vout]", "-map", "0:a?",
    "-shortest",
    "-c:v", "libx264", "-preset", "ultrafast", "-crf", "28",
    "-pix_fmt", "yuv420p",
    "-c:a", "copy",
    "-movflags", "+faststart",
    $out
)

$p = Start-Process -NoNewWindow -PassThru -Wait -FilePath "ffmpeg" -ArgumentList $ffArgs

if ($p.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $out)) {
    Write-Error "? ffmpeg 失敗 (ExitCode=$($p.ExitCode))"
    exit 1
}

# === バックアップ作成 ===
$bgExt      = [System.IO.Path]::GetExtension($bgFull)
$backupName = "{0}_backup_{1}{2}" -f $bgBase, (Get-Date -Format "yyyyMMddHHmmss"), $bgExt
$backupPath = Join-Path $bgDir $backupName

Copy-Item -LiteralPath $bgFull -Destination $backupPath -Force

# === 元の名前に差し替え ===
Copy-Item -LiteralPath $out -Destination $bgFull -Force

# === 完了メッセージ ===
Write-Host "? 完了: 左上に正方形オーバーレイしました"
Write-Host "   - 新しい動画: $bgFull"
Write-Host "   - バックアップ: $backupPath"
Write-Host "   - サイズ: 背景横幅の30% × 30%（強制正方形）"
Write-Host "   - 透過: $OverlayAlpha, マージン: $Margin px"
Write-Host "   - プリセット: ultrafast / CRF=28（速度優先）"