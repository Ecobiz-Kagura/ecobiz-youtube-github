param(
  [Parameter(Position=0, Mandatory=$true)]
  [string]$InputPs1,

  # 第2引数でBGMテーマ（例：epilogue）
  [Parameter(Position=1, Mandatory=$false)]
  [ValidateSet("none","epilogue","ghost","silent")]
  [string]$BgmTheme = "none"
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

function Pick-LatestAfter([string]$dir, [string]$pattern, [datetime]$after){
  if(-not (Test-Path -LiteralPath $dir)){ return $null }
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

  Fail "BGMスクリプトが存在しません: $p1 （または $p2）"
}

# ------------------------------------------------------------
# 0) 最初に確認（途中確認なし）
# ------------------------------------------------------------
$ps1 = (Resolve-Path -LiteralPath $InputPs1 -ErrorAction Stop).Path
$cwd = (Get-Location).Path

$wavPreview = Pick-LatestInDir -dir $cwd -pattern "*.wav"
$srtPreview = Pick-LatestInDir -dir $cwd -pattern "*.srt"
if(-not $wavPreview){ Fail "カレントに wav がありません: $cwd" }
if(-not $srtPreview){ Fail "カレントに srt がありません: $cwd" }

$bg  = Join-Path $cwd "11-oiran-okami.mp4"
$bgNote = if(Test-Path -LiteralPath $bg){""}else{"(未存在：ps1実行後に生成される可能性あり)"}

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$outOverlay = Join-Path $cwd ("overlay_{0}.mp4" -f $ts)

# 最終出力名（プレビュー）：srtと同名
$srtBasePreview = [IO.Path]::GetFileNameWithoutExtension($srtPreview.FullName)
$finalOutPreview = Join-Path $cwd ("{0}.mp4" -f $srtBasePreview)

$bgmScript = if($BgmTheme -ne "none"){ Resolve-BgmScript $BgmTheme } else { "" }

Write-Host ""
Write-Host "====================================================="
Write-Host "  ? 実行前確認（途中確認なし）"
Write-Host "-----------------------------------------------------"
Write-Host "  ps1         : $ps1"
Write-Host "  カレント    : $cwd"
Write-Host "  背景(mp4)   : $bg $bgNote"
Write-Host "  音声(wav)   : $($wavPreview.FullName)"
Write-Host "  字幕(srt)   : $($srtPreview.FullName)"
Write-Host "  作成MP4     :"
Write-Host "     overlay : $outOverlay"
Write-Host "     最終    : $finalOutPreview  （採用srtと同名）"
Write-Host "  BGMテーマ   : $BgmTheme"
if($bgmScript){ Write-Host "  BGMスクリプト: $bgmScript （引数=mp4を1個）" }
Write-Host "====================================================="
$ans = Read-Host "実行しますか？ (y/N)"
if($ans.ToLower() -ne "y"){
  Write-Host "キャンセルしました。"
  return
}

# ------------------------------------------------------------
# 1) 生成ps1 実行（中身は読まない・余計な引数は絶対渡さない）
# ------------------------------------------------------------
& $ps1

# 実行後に wav/srt が更新される可能性があるので、ここで「本採用」を取り直す（確認は入れない）
$wav = Pick-LatestInDir -dir $cwd -pattern "*.wav" ; if(-not $wav){ Fail "実行後も wav が見つかりません: $cwd" }
$srt = Pick-LatestInDir -dir $cwd -pattern "*.srt" ; if(-not $srt){ Fail "実行後も srt が見つかりません: $cwd" }

# 背景
if(-not (Test-Path -LiteralPath $bg)){
  Fail "背景mp4が見つかりません: $bg"
}

# 最終出力名（本採用srtに合わせて確定）
$srtBase  = [IO.Path]::GetFileNameWithoutExtension($srt.FullName)
$finalOut = Join-Path $cwd ("{0}.mp4" -f $srtBase)

# ------------------------------------------------------------
# 2) overlay 作成（字幕巨大化対策：original_size）
# ------------------------------------------------------------
$se = Esc-Subs $srt.FullName
$style = "FontSize=12,Alignment=2,MarginV=60,Outline=1,Shadow=0"

$fc = @(
  "[0:v]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,setsar=1[v0]",
  "[v0]subtitles='$se':original_size=1080x1920:force_style='$style'[vout]"
) -join ";"

ffmpeg -y -hide_banner `
  -i $bg `
  -i $wav.FullName `
  -filter_complex $fc `
  -map "[vout]" `
  -map "1:a:0" `
  -shortest `
  -c:v libx264 -preset veryfast -pix_fmt yuv420p -crf 18 `
  -c:a aac -b:a 192k `
  $outOverlay

if(-not (Test-Path -LiteralPath $outOverlay)){ Fail "overlayが生成されませんでした" }
Write-Host "Saved: $outOverlay"

# ------------------------------------------------------------
# 3) BGM（指定時：カレント最新mp4を1個だけ渡す）
# ------------------------------------------------------------
$baseForFinal = $outOverlay

if($BgmTheme -ne "none"){
  # ★BGMに渡す入力は「カレント最新mp4」に固定
  $mp4In = Get-ChildItem -LiteralPath $cwd -File -Filter "*.mp4" |
           Sort-Object LastWriteTime -Descending |
           Select-Object -First 1
  if(-not $mp4In){
    Fail "BGM前：カレントに mp4 がありません"
  }

  # 念のため overlay のほうが新しければ overlay を優先
  if((Get-Item -LiteralPath $outOverlay).LastWriteTime -gt $mp4In.LastWriteTime){
    $mp4In = Get-Item -LiteralPath $outOverlay
  }

  $mp4InPath = $mp4In.FullName
  if(-not (Test-Path -LiteralPath $mp4InPath)){
    Fail "BGM入力 mp4 が見つかりません: $mp4InPath"
  }

  $tBgm0 = Get-Date

  Write-Host ""
  Write-Host "===== BGM追加開始 ====="
  Write-Host "  テーマ         : $BgmTheme"
  Write-Host "  使用スクリプト : $bgmScript"
  Write-Host "  入力mp4(最新)  : $mp4InPath"
  Write-Host "======================="

  # ★あなたの希望：-Mp4 なし、引数は mp4 1個だけ
  & $bgmScript $mp4InPath

  # BGM後に作られた/更新された mp4 を拾う（更新でもOK）
  $mp4After = Pick-LatestAfter -dir $cwd -pattern "*.mp4" -after $tBgm0
  if(-not $mp4After){
    # 上書き型で秒が同じ等のフォールバック：最新を拾う
    $mp4After = Get-ChildItem -LiteralPath $cwd -File -Filter "*.mp4" |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1
  }
  if(-not $mp4After){
    Fail "BGM後：mp4 が見つかりません"
  }

  $baseForFinal = $mp4After.FullName
  Write-Host "BGM出力(採用): $baseForFinal"
}

# ------------------------------------------------------------
# 4) 最終出力を「srtと同名」に確定（上書き）
# ------------------------------------------------------------
Copy-Item -LiteralPath $baseForFinal -Destination $finalOut -Force
if(-not (Test-Path -LiteralPath $finalOut)){ Fail "最終出力が生成されませんでした" }

Write-Host "Saved(final): $finalOut"
Write-Host "完了しました。"
