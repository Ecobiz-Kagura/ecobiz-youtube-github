# ============================================================
# charamin-overlay.ps1 ?? 完全版（左半分問題を自動補正 / StrictMode-safe）
#
# 仕様（固定）:
#  - SetupScript は実行しない（検索ヒントのみ）
#  - 背景（base / under）= 第2引数 mp4（退避コピー）
#  - オーバーレイ（top / over）= WorkDir から自動選択 mp4
#  - ★オーバーレイが「左半分だけ前面」になる素材を自動判定して補正
#     - 典型: 3840x1080, 2560x720 など横がほぼ2倍の動画
#     - 自動で「左半分 crop → 1920x1080に拡大」
#  - ★オーバーレイの繰り返し防止: eof_action=pass:repeatlast=0
#  - 両方フルスクリーン（1920x1080）
#  - 音声 auto（mix/base/top）
#  - add-BGM-<Mode>.ps1 があれば実行
#  - ★.Path を使わない
#  - 最後に処理時間表示
#
# 実行:
#   .\charamin-overlay.ps1 <SetupScript> <OtherMP4> <Mode> <Kind>
# ============================================================

param(
  [Parameter(Mandatory=$true, Position=0)][string]$SetupScriptPath,
  [Parameter(Mandatory=$true, Position=1)][string]$OtherVideo,
  [Parameter(Mandatory=$true, Position=2)][string]$Mode,
  [Parameter(Mandatory=$true, Position=3)][string]$Kind,

  [int]$W = 1920,
  [int]$H = 1080,
  [int]$FPS = 30,

  [string]$WorkDir = "",

  [ValidateSet("auto","base","top","mix")]
  [string]$Audio = "auto",

  # 横2倍素材のとき「左」か「右」どちらを採用するか
  [ValidateSet("left","right")]
  [string]$Half = "left",

  [switch]$NoBgm,
  [string]$BgmDir = "",

  [string]$OutName = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$startedAt = Get-Date

try {

  function NormPath([string]$p){
    [string](Resolve-Path -LiteralPath $p -ErrorAction Stop)
  }

  function HasAudio([string]$p){
    $o = & ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 $p 2>$null
    -not [string]::IsNullOrWhiteSpace(($o | Out-String).Trim())
  }

  function GetVideoWH([string]$p){
    $line = & ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x $p 2>$null
    $s = ($line | Out-String).Trim()
    if($s -notmatch '^\d+x\d+$'){ return @{w=0;h=0} }
    $a = $s.Split('x')
    return @{w=[int]$a[0]; h=[int]$a[1]}
  }

  function InvokeBgm([string]$mode,[string]$video){
    if($NoBgm){ return }
    if([string]::IsNullOrWhiteSpace($BgmDir)){
      $BgmDir = Split-Path -Parent $PSCommandPath
    }
    $bgm = Join-Path $BgmDir ("add-BGM-{0}.ps1" -f $mode)
    if(Test-Path -LiteralPath $bgm){
      Write-Host ""
      Write-Host "BGM実行: $bgm"
      & $bgm $video
    } else {
      Write-Host "BGM: スキップ（見つからない）: $bgm"
    }
  }

  # ===== WorkDir =====
  if([string]::IsNullOrWhiteSpace($WorkDir)){
    $WorkDir = (Get-Location).ProviderPath
  }
  $work = NormPath $WorkDir

  # ===== OtherVideo（背景）=====
  if(-not (Test-Path -LiteralPath $OtherVideo)){
    throw "OtherVideo が見つかりません: $OtherVideo"
  }
  $otherOrig = NormPath $OtherVideo

  # 背景用に退避コピー（消失対策）
  $tmpDir = Join-Path (Get-Location) "_overlay_tmp"
  if(-not (Test-Path -LiteralPath $tmpDir)){
    New-Item -ItemType Directory -Path $tmpDir | Out-Null
  }
  $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
  $otherSafe = Join-Path $tmpDir ($stamp + "-" + [IO.Path]::GetFileName($otherOrig))
  Copy-Item -LiteralPath $otherOrig -Destination $otherSafe -Force

  # ===== SetupScript は検索ヒント =====
  $hint = [IO.Path]::GetFileNameWithoutExtension($SetupScriptPath)
  $hint = ($hint -replace '^\d+-','')

  # ===== overlay 用 mp4 を WorkDir から選択 =====
  $all = Get-ChildItem -LiteralPath $work -File -Filter *.mp4 -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -ne $otherOrig -and $_.FullName -ne $otherSafe } |
    Sort-Object LastWriteTimeUtc -Descending

  if(-not $all){
    throw "WorkDir 内に overlay 候補 mp4 がありません: $work"
  }

  $picked = $all | Where-Object { $_.Name -like "*$hint*" } | Select-Object -First 1
  if(-not $picked){
    $picked = $all | Select-Object -First 1
  }

  # ===== 上下関係（固定）=====
  $base = $otherSafe         # 背景 = 第2引数
  $top  = $picked.FullName   # 上 = WorkDir 自動選択

  # ===== top の「横2倍」自動判定 =====
  $whTop = GetVideoWH $top
  $needHalfCrop = $false

  # 横がほぼ2倍、縦がほぼ同等なら「左右2枚」素材とみなす
  if($whTop.w -ge ($W*2 - 32) -and $whTop.h -ge ($H - 32)){
    $needHalfCrop = $true
  }

  # ===== 音声 =====
  $baseHas = HasAudio $base
  $topHas  = HasAudio $top

  $audioMode = $Audio
  if($Audio -eq "auto"){
    if($baseHas -and $topHas){ $audioMode="mix" }
    elseif($baseHas){ $audioMode="base" }
    elseif($topHas){ $audioMode="top" }
    else{ $audioMode="base" }
  }

  $af=$null
  $mapA=@()
  switch($audioMode){
    "base" { $mapA=@("-map","0:a?") }
    "top"  { $mapA=@("-map","1:a?") }
    "mix"  {
      if($baseHas -and $topHas){
        $af="[0:a][1:a]amix=inputs=2:duration=longest:dropout_transition=0[a]"
        $mapA=@("-map","[a]")
      } elseif($baseHas){
        $mapA=@("-map","0:a?")
      } elseif($topHas){
        $mapA=@("-map","1:a?")
      } else {
        $mapA=@("-map","0:a?")
      }
    }
  }

  # ===== 出力 =====
  if([string]::IsNullOrWhiteSpace($OutName)){
    $OutName = "$stamp-$Mode-$Kind-fullblend.mp4"
  }
  $out = Join-Path (Get-Location) $OutName

  # ===== filter_complex =====
  $bgChain = "[0:v]fps=${FPS},scale=${W}:${H},setsar=1[bg];"

  if($needHalfCrop){
    # left or right
    $x = "0"
    if($Half -eq "right"){ $x = "iw/2" }

    # 左右2枚素材 → 半分だけ切り出してから全画面化
    $ovChain = "[1:v]crop=iw/2:ih:${x}:0,fps=${FPS},scale=${W}:${H},setsar=1,format=yuv420p[ov];"
  } else {
    $ovChain = "[1:v]fps=${FPS},scale=${W}:${H},setsar=1,format=yuv420p[ov];"
  }

  # ★繰り返し防止
  $mixChain = "[bg][ov]overlay=0:0:eof_action=pass:repeatlast=0[v]"
  $vf = $bgChain + $ovChain + $mixChain
  if($af){ $vf = "$vf;$af" }

  Write-Host ""
  Write-Host "===================="
  Write-Host "WorkDir     : $work"
  Write-Host "Hint        : $hint"
  Write-Host "Base(under) : $base"
  Write-Host "Top(over)   : $top"
  Write-Host "TopWH       : $($whTop.w)x$($whTop.h)  halfCrop=$needHalfCrop  half=$Half"
  Write-Host "Audio(mode) : $audioMode"
  Write-Host "Out         : $out"
  Write-Host "===================="
  Write-Host ""

  & ffmpeg -y `
    -i $base -i $top `
    -filter_complex $vf `
    -map "[v]" @mapA `
    -c:v libx264 -pix_fmt yuv420p `
    -c:a aac -movflags +faststart `
    $out

  InvokeBgm $Mode $out
}
finally{
  $sw.Stop()
  $e = $sw.Elapsed
  $sec  = [math]::Round($e.TotalSeconds, 1)
  $mmss = "{0:mm\:ss}" -f $e
  Write-Host ""
  Write-Host "========================="
  Write-Host "開始時刻 : $startedAt"
  Write-Host "終了時刻 : $(Get-Date)"
  Write-Host "処理時間 : $sec 秒 ($mmss)"
  Write-Host "========================="
}
