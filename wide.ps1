# make-youtube-wide-from-latest-wav.ps1
# 最新の *.wav と *.srt から 1920x1080(16:9) の YouTube 用 mp4 を作る（字幕：さらに約半分サイズ）
# ★FontSize デフォルト=13（前の 26 の約半分）
# ★PowerShell の "$Widthx$Height" 地雷を回避（-f で確実に組み立て）
# ★最後に必ず処理時間を表示（失敗しても finally で出る）
#
# 使い方:
#   powershell -ExecutionPolicy Bypass -File .\make-youtube-wide-from-latest-wav.ps1
#   .\make-youtube-wide-from-latest-wav.ps1 -FontSize 13 -Outline 0 -Shadow 0 -MarginV 40
#   .\make-youtube-wide-from-latest-wav.ps1 -WhatIf

param(
    [string]$OutName = "",

    # 画面（YouTubeワイド）
    [int]$Width = 1920,
    [int]$Height = 1080,
    [int]$Fps = 30,
    [string]$BgColor = "black",

    # 字幕（さらに小さめ：半分くらい）
    [int]$FontSize = 13,
    [int]$Outline = 0,
    [int]$Shadow = 0,
    [int]$MarginV = 40,

    # 音声
    [int]$AudioKbps = 192,

    # 実行制御
    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# =========================
# 処理時間計測開始
# =========================
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$startedAt = Get-Date

try {

    function Assert-Cmd([string]$name) {
        if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
            throw "コマンドが見つかりません: $name（ffmpeg を PATH に入れてください）"
        }
    }

    function Get-LatestFile([string]$pattern) {
        Get-ChildItem -File -Filter $pattern -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
    }

    # ffmpeg subtitles 用パス整形（Windows地雷回避）
    function To-FfmpegSubPath([string]$p) {
        $full = (Resolve-Path -LiteralPath $p).Path
        $full = $full -replace '\\','/'
        $full = $full -replace '^([A-Za-z]):/','$1\:/'
        $full = $full -replace "'","''"
        return $full
    }

    Assert-Cmd "ffmpeg"

    $wav = Get-LatestFile "*.wav"
    $srt = Get-LatestFile "*.srt"

    if (-not $wav) { throw "wav が見つかりません（カレントに *.wav が必要）" }
    if (-not $srt) { throw "srt が見つかりません（カレントに *.srt が必要）" }

    Write-Host ("WAV: {0}  ({1})" -f $wav.Name, $wav.LastWriteTime)
    Write-Host ("SRT: {0}  ({1})" -f $srt.Name, $srt.LastWriteTime)

    if ([string]::IsNullOrWhiteSpace($OutName)) {
        $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $base  = [IO.Path]::GetFileNameWithoutExtension($wav.Name)
        $OutName = "{0}_{1}_wide.mp4" -f $stamp, $base
    }
    $outPath = Join-Path (Get-Location) $OutName

    # -------------------------
    # フィルタ設定（字幕）
    # -------------------------
    $srtF = To-FfmpegSubPath $srt.FullName
    $forceStyle = "Fontsize=$FontSize,Outline=$Outline,Shadow=$Shadow,MarginV=$MarginV"
    $vf = "subtitles='$srtF':charenc=UTF-8:force_style='$forceStyle'"

    # ★背景生成（ここが地雷になりやすいので -f で確実に）
    if ([string]::IsNullOrWhiteSpace($BgColor)) { $BgColor = "black" }
    $colorSrc = ("color=c={0}:s={1}x{2}:r={3}" -f $BgColor, $Width, $Height, $Fps)

    $aBitrate = ("{0}k" -f $AudioKbps)

    Write-Host ""
    Write-Host "=== 設定 ==="
    Write-Host ("解像度: {0}x{1}  FPS: {2}  背景: {3}" -f $Width,$Height,$Fps,$BgColor)
    Write-Host ("字幕: FontSize={0} Outline={1} Shadow={2} MarginV={3}" -f $FontSize,$Outline,$Shadow,$MarginV)
    Write-Host ("音声: AAC {0}" -f $aBitrate)
    Write-Host ("出力: {0}" -f $outPath)
    Write-Host ""

    # 実行コマンド（配列で安全に渡す）
    $cmd = @(
        "ffmpeg",
        "-y",
        "-f","lavfi","-i",$colorSrc,
        "-i",$wav.FullName,
        "-vf",$vf,
        "-shortest",
        "-c:v","libx264",
        "-pix_fmt","yuv420p",
        "-profile:v","high",
        "-level","4.2",
        "-c:a","aac",
        "-b:a",$aBitrate,
        "-movflags","+faststart",
        $outPath
    )

    if ($WhatIf) {
        Write-Host "WhatIf: 実行コマンド"
        Write-Host ($cmd -join " ")
        return
    }

    Write-Host "開始..."
    & $cmd[0] $cmd[1..($cmd.Count-1)]

}
finally {
    $sw.Stop()
    $elapsed = $sw.Elapsed
    $totalSec = [math]::Round($elapsed.TotalSeconds, 1)
    $mmss = "{0:mm\:ss}" -f $elapsed

    Write-Host ""
    Write-Host "========================="
    Write-Host "開始時刻 : $startedAt"
    Write-Host "終了時刻 : $(Get-Date)"
    Write-Host "処理時間 : ${totalSec} 秒 (${mmss})"
    Write-Host "========================="
}
