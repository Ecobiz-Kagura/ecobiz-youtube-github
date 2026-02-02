param(
  [Parameter(Position=0, Mandatory=$true)]
  [string]$InputPs1,

  [Parameter(Position=1, Mandatory=$false)]
  [ValidateSet("none","epilogue","ghost","silent")]
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
  if(Test-Path $p1){ return $p1 }
  if(Test-Path $p2){ return $p2 }
  Fail "BGMスクリプトが見つかりません: $p1 または $p2"
}

function Get-LatestMp4AfterExcluding([string]$dir, [datetime]$after, [string[]]$excludePaths){
  $exclude = @{}
  foreach($e in $excludePaths){
    if($e -and (Test-Path $e)){
      $exclude[(Resolve-Path $e).Path.ToLower()] = $true
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
    if($e -and (Test-Path $e)){
      $exclude[(Resolve-Path $e).Path.ToLower()] = $true
    }
  }

  Get-ChildItem -LiteralPath $dir -File -Filter "*.mp4" -ErrorAction SilentlyContinue |
    Where-Object { -not $exclude[$_.FullName.ToLower()] } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
}

function Get-LatestMp4Background([string]$dir, [datetime]$cutoff, [string[]]$excludePaths){
  # 重要：
  # - 「カレントの最新 mp4」を背景にするが、
  #   overlay_*.mp4 等の “このスクリプトが今作るファイル” を誤って拾わないようにする
  # - $cutoff 以前（開始時刻）までに存在していた mp4 の中で最新を拾う（安全）
  $exclude = @{}
  foreach($e in $excludePaths){
    if($e -and (Test-Path $e)){
      $exclude[(Resolve-Path $e).Path.ToLower()] = $true
    }
  }

  $cand = Get-ChildItem -LiteralPath $dir -File -Filter "*.mp4" -ErrorAction SilentlyContinue |
    Where-Object {
      $_.LastWriteTime -le $cutoff `
        -and -not $exclude[$_.FullName.ToLower()] `
        -and $_.Name -notlike "overlay_*.mp4"
    } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

  if(-not $cand){
    # フォールバック：cutoff 条件を外して “とにかく最新” を拾う（ただし overlay_ は除外）
    $cand = Get-ChildItem -LiteralPath $dir -File -Filter "*.mp4" -ErrorAction SilentlyContinue |
      Where-Object {
        -not $exclude[$_.FullName.ToLower()] -and $_.Name -notlike "overlay_*.mp4"
      } |
      Sort-Object LastWriteTime -Descending |
      Select-Object -First 1
  }

  if(-not $cand){
    Fail "カレントディレクトリに mp4 がありません。背景MP4を決定できません。"
  }
  return $cand.FullName
}

function Assert-Command([string]$name){
  $cmd = Get-Command $name -ErrorAction SilentlyContinue
  if(-not $cmd){ Fail "$name が見つかりません。PATH を確認してください。" }
}

# ------------------------------------------------------------
# 0) 事前情報
# ------------------------------------------------------------
$runStart = Get-Date
$ps1 = (Resolve-Path $InputPs1).Path
$cwd = (Get-Location).Path

Assert-Command "ffmpeg"

$wavPrev = Pick-LatestInDir $cwd "*.wav"
$srtPrev = Pick-LatestInDir $cwd "*.srt"

# 旧ファイルが無いケースもあるので、表示だけ優先
$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$outOverlayPrev = Join-Path $cwd ("overlay_{0}.mp4" -f $ts)

# srtPrev が無い場合でもここで落とさない（生成ps1後に確定する）
$finalPrev = if($srtPrev){
  $srtBasePrev = [IO.Path]::GetFileNameWithoutExtension($srtPrev.FullName)
  Join-Path $cwd ("{0}.mp4" -f $srtBasePrev)
}else{
  Join-Path $cwd ("final_{0}.mp4" -f $ts)
}

$bgmScript = Resolve-BgmScript $BgmTheme
$uploader = Join-Path $cwd "uploader11.py"

# 背景MP4（＝カレントの最新mp4）を “開始時点” 基準で安全に決定
# 生成される overlay_*.mp4 を誤って拾わないよう exclude に outOverlayPrev を入れておく
$bg = Get-LatestMp4Background $cwd $runStart @($outOverlayPrev, $finalPrev)
Write-Host "背景MP4(最新): $bg"

# ------------------------------------------------------------
# 1) 予定表示
# ------------------------------------------------------------
Write-Host ""
Write-Host "====================================================="
Write-Host "  実行予定"
Write-Host "====================================================="
Write-Host "生成 ps1:       $ps1"
Write-Host "背景 mp4:       $bg"
Write-Host "overlay 出力:   $outOverlayPrev"
Write-Host "最終出力(予定): $finalPrev"
Write-Host "BGM:            $BgmTheme"
if(-not $SkipUpload){
  Write-Host "uploader11.py:  python uploader11.py --mode $UploadMode"
}else{
  Write-Host "uploader:       スキップ"
}
Write-Host ""
$ans = Read-Host "実行しますか？ (y/N)"
if($ans.ToLower() -ne "y"){ return }

# ------------------------------------------------------------
# 2) 生成 ps1 実行
# ------------------------------------------------------------
& $ps1

$wav = Pick-LatestInDir $cwd "*.wav"
$srt = Pick-LatestInDir $cwd "*.srt"
if(-not $wav){ Fail "wav が見つかりません（生成ps1の出力を確認）: $cwd" }
if(-not $srt){ Fail "srt が見つかりません（生成ps1の出力を確認）: $cwd" }

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

ffmpeg -y -hide_banner `
  -i $bg `
  -i $wav.FullName `
  -filter_complex $fc `
  -map "[vout]" -map "1:a:0" `
  -shortest `
  -c:v libx264 -preset veryfast -pix_fmt yuv420p -crf 18 `
  -c:a aac -b:a 192k `
  $outOverlayPrev

if($LASTEXITCODE -ne 0 -or -not (Test-Path $outOverlayPrev)){
  Fail "overlay 作成に失敗しました。背景MP4=$bg / wav=$($wav.FullName) / srt=$($srt.FullName)"
}

$baseForFinal = $outOverlayPrev

# ------------------------------------------------------------
# 4) BGM
# ------------------------------------------------------------
if($BgmTheme -ne "none"){
  if(-not (Test-Path $baseForFinal)){
    Fail "BGM前の入力MP4が存在しません: $baseForFinal"
  }

  $exclude = @($bg, $outOverlayPrev, $finalOut)
  $t0 = Get-Date

  & $bgmScript $baseForFinal

  $newMp4 = Get-LatestMp4AfterExcluding $cwd $t0 ($exclude + $baseForFinal)
  if(-not $newMp4){
    $newMp4 = Get-LatestMp4Excluding $cwd ($exclude + $baseForFinal)
  }
  if(-not $newMp4){
    Fail "BGM後の mp4 が見つかりません（BGMスクリプトの出力を確認）"
  }

  $baseForFinal = $newMp4.FullName
}

# ------------------------------------------------------------
# 5) srt と同名で保存
# ------------------------------------------------------------
Copy-Item $baseForFinal $finalOut -Force
Write-Host "Saved final: $finalOut"

# ------------------------------------------------------------
# 6) upload（任意）
# ------------------------------------------------------------
if(-not $SkipUpload){
  if(-not (Test-Path $uploader)){
    Write-Host "[WARN] uploader11.py が見つからないためアップロードをスキップしました: $uploader"
  }else{
    # 既存運用に合わせて “--mode だけ” 実行（uploader側で最新を拾う想定）
    python $uploader --mode $UploadMode
    if($LASTEXITCODE -ne 0){
      Fail "アップロードに失敗しました: python uploader11.py --mode $UploadMode"
    }
  }
}
