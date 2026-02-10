param(
  [Parameter(Position=0, Mandatory=$true)]
  [string]$InputPs1,

  [Parameter(Position=1, Mandatory=$false)]
  [ValidateSet("none","epilogue","ghost","silent","twilight")]
  [string]$BgmTheme = "none",

  # 名前付きで指定（例: -UploadMode kankyou）
  [Parameter(Mandatory=$false)]
  [string]$UploadMode = "kankyou",

  # アップロードをスキップ
  [Parameter(Mandatory=$false)]
  [switch]$SkipUpload
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

function Get-LatestMp4AfterExcluding([string]$dir, [datetime]$after, [string[]]$excludePaths){
  $exclude = @{}
  foreach($e in $excludePaths){
    if($e -and (Test-Path -LiteralPath $e)){
      $exclude[(Resolve-Path -LiteralPath $e).Path.ToLower()] = $true
    }
  }

  Get-ChildItem -LiteralPath $dir -File -Filter "*.mp4" -ErrorAction SilentlyContinue |
    Where-Object {
      $_.LastWriteTime -ge $after -and -not $exclude[$_.FullName.ToLower()]
    } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
}

function Get-LatestMp4Excluding([string]$dir, [string[]]$excludePaths){
  $exclude = @{}
  foreach($e in $excludePaths){
    if($e -and (Test-Path -LiteralPath $e)){
      $exclude[(Resolve-Path -LiteralPath $e).Path.ToLower()] = $true
    }
  }

  Get-ChildItem -LiteralPath $dir -File -Filter "*.mp4" -ErrorAction SilentlyContinue |
    Where-Object { -not $exclude[$_.FullName.ToLower()] } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
}

function Get-TargetMp4([string]$dir, [datetime]$since, [string[]]$excludePaths){
  # 1) 「今回作成（更新）された最新 mp4」（since 以降）を優先
  $m = Get-LatestMp4AfterExcluding $dir $since $excludePaths
  if($m){ return $m.FullName }

  # 2) 無ければ「カレントの最新 mp4」にフォールバック
  $m = Get-LatestMp4Excluding $dir $excludePaths
  if($m){ return $m.FullName }

  return $null
}

# ------------------------------------------------------------
# 0) 事前情報
# ------------------------------------------------------------
$scriptStart = Get-Date

$ps1 = (Resolve-Path -LiteralPath $InputPs1 -ErrorAction Stop).Path
$cwd = (Get-Location).Path

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$outOverlay = Join-Path $cwd ("overlay_{0}.mp4" -f $ts)

$bgmScript = Resolve-BgmScript $BgmTheme
$uploader = Join-Path $cwd "uploader11.py"

# 予定表示用（存在しない可能性があるので null 許容）
$wavPrev = Pick-LatestInDir $cwd "*.wav"
$srtPrev = Pick-LatestInDir $cwd "*.srt"
$finalPrev = $null
if($srtPrev){
  $srtBasePrev = [IO.Path]::GetFileNameWithoutExtension($srtPrev.FullName)
  $finalPrev = Join-Path $cwd ("{0}.mp4" -f $srtBasePrev)
}

# ------------------------------------------------------------
# 1) 予定表示
# ------------------------------------------------------------
Write-Host ""
Write-Host "====================================================="
Write-Host "  実行予定"
Write-Host "====================================================="
Write-Host "生成 ps1:        $ps1"
Write-Host "overlay 出力:     $outOverlay"
if($finalPrev){
  Write-Host "最終出力(予定):   $finalPrev"
}else{
  Write-Host "最終出力(予定):   （srt未検出のため後で確定）"
}
Write-Host "BGM:              $BgmTheme"
Write-Host "処理対象mp4:      カレントで今回作成された最新mp4（無ければ最新mp4）"
if(-not $SkipUpload){
  Write-Host "uploader11.py:    python uploader11.py --mode $UploadMode"
}else{
  Write-Host "uploader:         スキップ"
}
Write-Host ""
$ans = Read-Host "実行しますか？ (y/N)"
if($ans.ToLower() -ne "y"){ return }

# ------------------------------------------------------------
# 2) 生成 ps1 実行
# ------------------------------------------------------------
& $ps1
if($LASTEXITCODE -ne 0){
  Fail "生成 ps1 が異常終了しました: $ps1"
}

$wav = Pick-LatestInDir $cwd "*.wav"
$srt = Pick-LatestInDir $cwd "*.srt"
if(-not $wav){ Fail "wav が見つかりません（生成 ps1 の出力を確認）" }
if(-not $srt){ Fail "srt が見つかりません（生成 ps1 の出力を確認）" }

$srtBase = [IO.Path]::GetFileNameWithoutExtension($srt.FullName)
$finalOut = Join-Path $cwd ("{0}.mp4" -f $srtBase)

# ------------------------------------------------------------
# 3) overlay 作成（背景 = “今回作成された最新mp4”）
# ------------------------------------------------------------
# overlay/最終名など、明らかに対象外にしたいもの
$excludeForBg = @($outOverlay, $finalOut)

# “今回作成された最新mp4” を背景として選ぶ（無ければ最新mp4）
$bg = Get-TargetMp4 $cwd $scriptStart $excludeForBg
if(-not $bg){
  Fail "処理対象の mp4 が見つかりません（カレントに mp4 がありません）"
}
Write-Host "背景（処理対象）: $bg"

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
  -map "[vout]" -map "1:a:0" `
  -shortest `
  -c:v libx264 -preset veryfast -pix_fmt yuv420p -crf 18 `
  -c:a aac -b:a 192k `
  $outOverlay

if($LASTEXITCODE -ne 0){
  Fail "ffmpeg(overlay) が失敗しました。背景mp4や音声パスを確認してください。背景: $bg"
}
if(-not (Test-Path -LiteralPath $outOverlay)){
  Fail "overlay 出力が生成されませんでした: $outOverlay"
}

$baseForFinal = $outOverlay

# ------------------------------------------------------------
# 4) BGM
# ------------------------------------------------------------
if($BgmTheme -ne "none"){
  $exclude = @($bg, $outOverlay, $finalOut, $baseForFinal)
  $t0 = Get-Date

  & $bgmScript $baseForFinal
  if($LASTEXITCODE -ne 0){
    Fail "BGMスクリプトが異常終了しました: $bgmScript"
  }

  $newMp4 = Get-LatestMp4AfterExcluding $cwd $t0 $exclude
  if(-not $newMp4){
    $newMp4 = Get-LatestMp4Excluding $cwd $exclude
  }
  if(-not $newMp4){
    Fail "BGM後の mp4 が見つかりません（BGMスクリプトの出力を確認）"
  }

  $baseForFinal = $newMp4.FullName
  Write-Host "BGM後 mp4: $baseForFinal"
}

# ------------------------------------------------------------
# 5) srt と同名で保存
# ------------------------------------------------------------
Copy-Item -LiteralPath $baseForFinal -Destination $finalOut -Force
Write-Host "Saved final: $finalOut"

# ------------------------------------------------------------
# 6) uploader（mode の検証なし）
# ------------------------------------------------------------
if(-not $SkipUpload){
  if(-not (Test-Path -LiteralPath $uploader)){
    Fail "uploader11.py が見つかりません: $uploader"
  }

  Write-Host ""
  Write-Host "Uploader 実行: python uploader11.py --mode $UploadMode"
  & python $uploader --mode $UploadMode
  if($LASTEXITCODE -ne 0){
    Fail "uploader11.py が異常終了しました。"
  }
}

Write-Host "完了しました。"
