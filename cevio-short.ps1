param(
  [Parameter(Position=0, Mandatory=$true)]
  [string]$InputPs1
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Fail([string]$msg){ throw "[ERROR] $msg" }

function Pick-LatestInDir([string]$dir, [string]$pattern){
  if(-not (Test-Path -LiteralPath $dir)){ return $null }
  Get-ChildItem -LiteralPath $dir -File -Filter $pattern -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
}

function Esc-ForSubtitles([string]$p){
  $x = $p -replace "\\","/"
  $x = $x -replace ":","\:"
  $x = $x -replace "'","\'"
  return $x
}

# ---- ここは「読む」ではなくパス解決だけ（中身は読まない）----
$ps1 = (Resolve-Path -LiteralPath $InputPs1 -ErrorAction Stop).Path
$cwd = (Get-Location).Path

# ---- 「確認のために」先に素材を確定（カレントの最新）----
$wav = Pick-LatestInDir -dir $cwd -pattern "*.wav"  ; if(-not $wav){ Fail "カレントに wav がありません: $cwd" }
$srt = Pick-LatestInDir -dir $cwd -pattern "*.srt"  ; if(-not $srt){ Fail "カレントに srt がありません: $cwd" }

# 背景は固定（あなたの指定）
$bg  = Join-Path $cwd "11-oiran-okami.mp4"
if(-not (Test-Path -LiteralPath $bg)){
  # 背景がまだ無いなら、実行後にできる可能性はあるが、確認前に分かるように表示だけする
  $bgNote = "(未存在：実行後に作られる想定)"
}else{
  $bgNote = ""
}

# ---- これから作る2つの mp4 名は先に決める（確認のため）----
$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$outOverlay = Join-Path $cwd ("overlay_{0}.mp4" -f $ts)
$outShort   = Join-Path $cwd ("overlay_{0}-short.mp4" -f $ts)

Write-Host ""
Write-Host "====================================================="
Write-Host "  ? これから実行する処理（最初に確認）"
Write-Host "-----------------------------------------------------"
Write-Host "  実行するPS1 : $ps1"
Write-Host "  背景(mp4)   : $bg $bgNote"
Write-Host "  音声(wav)   : $($wav.FullName)"
Write-Host "  字幕(srt)   : $($srt.FullName)"
Write-Host ""
Write-Host "  作成される MP4:"
Write-Host "    1) Overlay動画 : $outOverlay"
Write-Host "    2) Short版     : $outShort"
Write-Host "====================================================="
Write-Host ""
$ans = Read-Host "実行しますか？ (y/N)"
if($ans.ToLower() -ne "y"){
  Write-Host "キャンセルしました。"
  return
}

# ------------------------------------------------------------
# ここから本処理
# 1) 11-oiran-okami.ps1 を「余計な引数なし」で実行
# ------------------------------------------------------------
& $ps1  # ← 余計な引数は絶対に付けない

# 背景が実行後に作られる可能性があるので、ここで再チェック
if(-not (Test-Path -LiteralPath $bg)){
  Fail "背景 mp4 が見つかりません: $bg"
}

# ------------------------------------------------------------
# 2) overlay mp4 を必ず作る（背景=11-oiran-okami.mp4、音声=最新wav、字幕=最新srt）
# ------------------------------------------------------------
$se = Esc-ForSubtitles $srt.FullName
$style = "FontSize=46,Alignment=2,MarginV=110,Outline=2,Shadow=0"

$fc = @(
  "[0:v]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,setsar=1[v0]",
  "[v0]subtitles='$se':force_style='$style'[vout]"
) -join ";"

& ffmpeg -y -hide_banner `
  -i $bg `
  -i $wav.FullName `
  -filter_complex $fc `
  -map "[vout]" `
  -map "1:a:0" `
  -shortest `
  -c:v libx264 -preset veryfast -pix_fmt yuv420p -crf 18 `
  -c:a aac -b:a 192k `
  $outOverlay

Write-Host "Saved: $outOverlay"

# ------------------------------------------------------------
# 3) short 版を作る
# ------------------------------------------------------------
& ffmpeg -y -hide_banner `
  -i $outOverlay `
  -vf "scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,setsar=1" `
  -c:v libx264 -preset veryfast -pix_fmt yuv420p -crf 18 `
  -c:a aac -b:a 192k `
  $outShort

Write-Host "Saved: $outShort"
