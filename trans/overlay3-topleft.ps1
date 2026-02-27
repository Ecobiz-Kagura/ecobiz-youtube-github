param(
    [Parameter(Mandatory=$true)][string]$BackgroundVideoPath,  # 背景動画 (例: A.mp4)
    [Parameter(Mandatory=$true)][string]$OverlayVideoPath,     # オーバーレイ動画
    [int]$Margin = 10,              # 左上マージン(px)
    [double]$OverlayAlpha = 0.6     # 透過度（1.0=不透明）
)

# === 入力チェック ===
if (-not (Test-Path -LiteralPath $BackgroundVideoPath)) { Write-Error "背景動画が見つかりません: $BackgroundVideoPath"; exit 1 }
if (-not (Test-Path -LiteralPath $OverlayVideoPath))    { Write-Error "オーバーレイ動画が見つかりません: $OverlayVideoPath"; exit 1 }
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue))  { Write-Error "ffmpeg が見つかりません";  exit 1 }

# === 出力ファイル名（仮） ===
$out = [System.IO.Path]::ChangeExtension($BackgroundVideoPath, $null) + "_overlaySquare50.mp4"

# === filter_complex ===
# 横幅 = 背景の50% → 高さも同じ → 正方形に変形 ########  0.3

$filter = "[1:v][0:v]scale2ref=w=main_w*0.3:h=main_w*0.3[ovl][base];" +
          "[ovl]format=yuva420p,colorchannelmixer=aa=${OverlayAlpha}[ovla];" +
          "[base][ovla]overlay=${Margin}:${Margin}:format=auto[vout]"

# === ffmpeg 実行 ===
$ffArgs = @(
  "-y",
  "-i", $BackgroundVideoPath,
  "-stream_loop","-1","-i", $OverlayVideoPath,
  "-filter_complex", $filter,
  "-map","[vout]","-map","0:a?",
  "-shortest",
  "-c:v","libx264","-preset","ultrafast","-crf","28",
  "-pix_fmt","yuv420p",
  "-c:a","copy",
  "-movflags","+faststart",
  $out
)

$p = Start-Process -NoNewWindow -PassThru -Wait -FilePath "ffmpeg" -ArgumentList $ffArgs
if ($p.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $out)) {
    Write-Error "? ffmpeg 失敗 (ExitCode=$($p.ExitCode))"
    exit 1
}

# === バックアップ作成 ===
$backupPath = [System.IO.Path]::ChangeExtension($BackgroundVideoPath, $null) + "_backup_" + (Get-Date -Format "yyyyMMddHHmmss") + [System.IO.Path]::GetExtension($BackgroundVideoPath)
Copy-Item -LiteralPath $BackgroundVideoPath -Destination $backupPath -Force

# === 元の名前に差し替え ===
Copy-Item -LiteralPath $out -Destination $BackgroundVideoPath -Force

# === 完了メッセージ ===
Write-Host "? 完了: 左上に正方形オーバーレイしました"
Write-Host "   - 新しい動画: $BackgroundVideoPath"
Write-Host "   - バックアップ: $backupPath"
Write-Host "   - サイズ: 背景横幅の50% × 50%（強制正方形）"
Write-Host "   - 透過: $OverlayAlpha, マージン: $Margin px"
Write-Host "   - プリセット: ultrafast / CRF=28（速度優先）"
