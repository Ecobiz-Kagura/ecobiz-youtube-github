param(
  [Parameter(Position=0, Mandatory=$true)]
  [string]$InputPs1,

  [Parameter(Position=1, Mandatory=$false)]
  [ValidateSet("none","epilogue","ghost","silent")]
  [string]$BgmTheme = "none"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Fail([string]$msg){ throw "[ERROR] $msg" }

function Pick-LatestInDir([string]$dir, [string]$pattern){
  Get-ChildItem -LiteralPath $dir -File -Filter $pattern -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
}

function Pick-LatestAfter([string]$dir, [string]$pattern, [datetime]$after){
  Get-ChildItem -LiteralPath $dir -File -Filter $pattern -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -ge $after } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
}

function Esc-Subs([string]$p){
  ($p -replace "\\","/" -replace ":","\:" -replace "'","\'")
}

function Resolve-BgmScript([string]$theme){
  if($theme -eq "none"){ return "" }
  $p1 = Join-Path $PSScriptRoot ("add-BGM-{0}.ps1" -f $theme)
  $p2 = Join-Path $PSScriptRoot ("add_BGM_{0}.ps1" -f $theme)
  if(Test-Path -LiteralPath $p1){ return $p1 }
  if(Test-Path -LiteralPath $p2){ return $p2 }
  Fail "BGMスクリプトが見つかりません: $p1 または $p2"
}

# ------------------------------------------------------------
# 0) 情報収集（プレビュー用）
# ------------------------------------------------------------
$ps1 = (Resolve-Path -LiteralPath $InputPs1 -ErrorAction Stop).Path
$cwd = (Get-Location).Path

$wavPrev = Pick-LatestInDir -dir $cwd -pattern "*.wav"
if(-not $wavPrev){ Fail "カレントに wav がありません。" }

$srtPrev = Pick-LatestInDir -dir $cwd -pattern "*.srt"
if(-not $srtPrev){ Fail "カレントに srt がありません。" }

$bg = Join-Path $cwd "11-oiran-okami.mp4"
if(-not (Test-Path -LiteralPath $bg)){
  Write-Host "[WARN] 背景 mp4 がありません（ps1 実行後に生成される可能性あり）"
}

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$outOverlayPrev = Join-Path $cwd ("overlay_{0}.mp4" -f $ts)

$srtBasePrev = [IO.Path]::GetFileNameWithoutExtension($srtPrev.FullName)
$finalPrev = Join-Path $cwd ("{0}.mp4" -f $srtBasePrev)

$bgmScript = Resolve-BgmScript $BgmTheme

# ------------------------------------------------------------
# 1) 実行予定コマンドの一覧を表示（最初の一回だけ）
# ------------------------------------------------------------
Write-Host ""
Write-Host "====================================================="
Write-Host "    ??? 実行予定のコマンド一覧（確認後に実行）"
Write-Host "====================================================="
Write-Host ""
Write-Host "● 生成 ps1:"
Write-Host "    & $ps1"
Write-Host ""
Write-Host "● overlay ffmpeg（予定）:"
Write-Host ("    ffmpeg -i 11-oiran-okami.mp4 -i {0} ..." -f $wavPrev.FullName)
Write-Host "    出力 => $outOverlayPrev"
Write-Host ""
if($BgmTheme -ne "none"){
  Write-Host "● BGMスクリプト:"
  Write-Host "    & $bgmScript <最新mp4>"
  Write-Host ("    （最終出力 => {0})" -f $finalPrev)
}else{
  Write-Host "● BGMなしモード"
}
Write-Host ""
Write-Host "====================================================="
$ans = Read-Host "実行しますか？ (y/N)"
if($ans.ToLower() -ne "y"){
  Write-Host "キャンセルしました。"
  return
}

# ------------------------------------------------------------
# 2) ps1 実行
# ------------------------------------------------------------
& $ps1

# 実行後の最新 wav/srt を採用
$wav = Pick-LatestInDir -dir $cwd -pattern "*.wav"
$srt = Pick-LatestInDir -dir $cwd -pattern "*.srt"
if(-not $wav){ Fail "実行後 wav が見つかりません。" }
if(-not $srt){ Fail "実行後 srt が見つかりません。" }

if(-not (Test-Path -LiteralPath $bg)){
  Fail "背景 11-oiran-okami.mp4 が見つかりません。"
}

# 最終ファイル名は srt と同名
$srtBase = [IO.Path]::GetFileNameWithoutExtension($srt.FullName)
$finalOut = Join-Path $cwd ("{0}.mp4" -f $srtBase)

# ------------------------------------------------------------
# 3) overlay 作成
# ------------------------------------------------------------
$se = Esc-Subs $srt.FullName
$style = "FontSize=12,Alignment=2,MarginV=60,Outline=1,Shadow=0"

$fc = @(
  "[0:v]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,setsar=1[v0]",
  "[v0]subtitles='$se':original_size=1080x1920:force_style='$style'[vout]"
) -join ";"

$outOverlay = $outOverlayPrev

ffmpeg -y -hide_banner `
  -i $bg `
  -i $wav.FullName `
  -filter_complex $fc `
  -map "[vout]" -map "1:a:0" `
  -shortest `
  -c:v libx264 -preset veryfast -pix_fmt yuv420p -crf 18 `
  -c:a aac -b:a 192k `
  $outOverlay

Write-Host "Saved overlay: $outOverlay"

# ------------------------------------------------------------
# 4) BGM追加（最新mp4を渡す）
# ------------------------------------------------------------
$baseForFinal = $outOverlay

if($BgmTheme -ne "none"){
  $mp4In = Get-ChildItem -LiteralPath $cwd -File -Filter "*.mp4" |
           Sort-Object LastWriteTime -Descending |
           Select-Object -First 1

  if((Get-Item -LiteralPath $outOverlay).LastWriteTime -gt $mp4In.LastWriteTime){
    $mp4In = Get-Item -LiteralPath $outOverlay
  }

  Write-Host "BGM入力 mp4: $($mp4In.FullName)"
  $t0 = Get-Date

  & $bgmScript $mp4In.FullName

  $mp4After = Pick-LatestAfter -dir $cwd -pattern "*.mp4" -after $t0
  if(-not $mp4After){
    $mp4After = Get-ChildItem -LiteralPath $cwd -File -Filter "*.mp4" |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1
  }

  $baseForFinal = $mp4After.FullName
  Write-Host "BGM出力（採用）: $baseForFinal"
}

# ------------------------------------------------------------
# 5) 最終出力（srt と同名で保存）
# ------------------------------------------------------------
Copy-Item -LiteralPath $baseForFinal -Destination $finalOut -Force
Write-Host "Saved final: $finalOut"
Write-Host "完了しました。"
