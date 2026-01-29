param(
  [Parameter(Position=0, Mandatory=$true)]
  [string]$InputPs1
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Fail([string]$msg){ throw "[ERROR] $msg" }
function Info([string]$msg){ Write-Host "[INFO] $msg" }

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

# ----------------------------
# 事前確認（最初に止められる）
# ----------------------------
$ps1 = (Resolve-Path -LiteralPath $InputPs1 -ErrorAction Stop).Path
$cwd = (Get-Location).Path

$wav = Pick-LatestInDir -dir $cwd -pattern "*.wav" ; if(-not $wav){ Fail "カレントに wav がありません: $cwd" }
$srt = Pick-LatestInDir -dir $cwd -pattern "*.srt" ; if(-not $srt){ Fail "カレントに srt がありません: $cwd" }

$bg = Join-Path $cwd "11-oiran-okami.mp4"
$bgNote = if(Test-Path -LiteralPath $bg){ "" } else { "(未存在：実行後に作られる想定)" }

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$outOverlay = Join-Path $cwd ("overlay_{0}.mp4" -f $ts)
$outShort   = Join-Path $cwd ("overlay_{0}-short.mp4" -f $ts)

Write-Host ""
Write-Host "====================================================="
Write-Host "  ? 実行前確認"
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

# ----------------------------
# 本処理
# ----------------------------

# ★中身を読まない・余計な引数を渡さない
& $ps1

# 背景が実行後に生成される想定なので再チェック
if(-not (Test-Path -LiteralPath $bg)){
  Fail "背景 mp4 が見つかりません: $bg"
}

# ----------------------------
# overlay mp4 作成（字幕巨大化対策：original_size 指定）
# ----------------------------
$se = Esc-ForSubtitles $srt.FullName

# ※巨大化の主因：libassの基準解像度ズレ → original_size で固定
# フォントは控えめ（まずは 34 を基準に）
#$style = "FontSize=34,Alignment=2,MarginV=90,Outline=2,Shadow=0"
$style = "FontSize=12,Alignment=2,MarginV=60,Outline=1,Shadow=0"


$fc = @(
  "[0:v]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,setsar=1[v0]",
  "[v0]subtitles='$se':original_size=1080x1920:force_style='$style'[vout]"
) -join ";"

Info "filter_complex: $fc"
Info "overlay 作成 → $outOverlay"

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

Info "Saved: $outOverlay"

# ----------------------------
# short 版（overlay完成版をそのまま short に）
# ----------------------------
Info "short 作成 → $outShort"

& ffmpeg -y -hide_banner `
  -i $outOverlay `
  -vf "scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,setsar=1" `
  -c:v libx264 -preset veryfast -pix_fmt yuv420p -crf 18 `
  -c:a aac -b:a 192k `
  $outShort

Info "Saved: $outShort"
Info "完了"
