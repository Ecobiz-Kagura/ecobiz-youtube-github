# ============================================================
# charamin-overlay.ps1  ?? 完全版（.Path完全排除 / StrictMode-safe）
#
# 仕様（固定）:
#  - SetupScript は実行しない（変更不可＆.Path地雷回避）。検索ヒントのみ。
#  - 背景（base / under）= 第2引数 mp4（OtherMP4）の退避コピー
#  - オーバーレイ（top / over）= WorkDir から自動選択した mp4
#  - どちらも必ず全画面（scale=1920x1080）で合成
#  - 音声は auto（両方あればmix / 片方ならそれ）
#  - BGM は add-BGM-<Mode>.ps1 が存在すれば実行（無ければスキップ）
#  - ★ .Path プロパティはスクリプト内で一切使わない（完全排除）
#  - 最後に必ず処理時間表示
#
# 実行:
#   .\charamin-overlay.ps1 <SetupScript> <OtherMP4> <Mode> <Kind>
# ============================================================

param(
  [Parameter(Mandatory=$true, Position=0)][string]$SetupScriptPath,
  [Parameter(Mandatory=$true, Position=1)][string]$OtherVideo,
  [Parameter(Mandatory=$true, Position=2)][string]$Mode,
  [Parameter(Mandatory=$true, Position=3)][string]$Kind,

  [ValidateRange(0.0,1.0)][double]$Opacity = 0.55,

  [int]$W = 1920,
  [int]$H = 1080,
  [int]$FPS = 30,

  [string]$WorkDir = "",

  [ValidateSet("auto","base","top","mix")]
  [string]$Audio = "auto",

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

  function InvokeBgm([string]$mode,[string]$video){
    if($NoBgm){ return }

    # ★.Path 排除：既定ディレクトリは $PSCommandPath から算出
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

  # ========= WorkDir =========
  if([string]::IsNullOrWhiteSpace($WorkDir)){
    $WorkDir = (Get-Location).ProviderPath
  }
  $work = NormPath $WorkDir

  # ========= OtherVideo（背景） =========
  if(-not (Test-Path -LiteralPath $OtherVideo)){
    throw "OtherVideo が見つかりません: $OtherVideo"
  }
  $otherOrig = NormPath $OtherVideo

  # 消失対策：OtherVideo を退避コピー（背景はこのコピーを使う）
  $tmpDir = Join-Path (Get-Location) "_overlay_tmp"
  if(-not (Test-Path -LiteralPath $tmpDir)){
    New-Item -ItemType Directory -Path $tmpDir | Out-Null
  }
  $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
  $otherSafe = Join-Path $tmpDir ($stamp + "-" + [IO.Path]::GetFileName($otherOrig))
  Copy-Item -LiteralPath $otherOrig -Destination $otherSafe -Force

  # ========= SetupScript は検索ヒント =========
  $hint = [IO.Path]::GetFileNameWithoutExtension($SetupScriptPath)
  $hint = ($hint -replace '^\d+-','')  # 11-xxx → xxx

  # ========= WorkDir から overlay（上）を選ぶ =========
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

  # ========= 上下関係（固定：逆にする） =========
  # 背景（base）= 第2引数（退避コピー）
  $base = $otherSafe
  # オーバーレイ（top）= WorkDir 自動選択
  $top  = $picked.FullName

  # ========= 音声（auto） =========
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

  # ========= 出力名 =========
  if([string]::IsNullOrWhiteSpace($OutName)){
    $OutName = "$stamp-$Mode-$Kind-fullblend.mp4"
  }
  $out = Join-Path (Get-Location) $OutName

  # ========= filter_complex（両方フルスクリーン保証） =========
  $op = $Opacity.ToString([Globalization.CultureInfo]::InvariantCulture)

  # ★ ${W}:${H} で $W: 地雷回避
  $vf = "[0:v]fps=${FPS},scale=${W}:${H},setsar=1[bg];" +
        "[1:v]fps=${FPS},scale=${W}:${H},setsar=1,format=rgba,colorchannelmixer=aa=${op}[ov];" +
        "[bg][ov]overlay=0:0[v]"
  if($af){ $vf = "$vf;$af" }

  Write-Host ""
  Write-Host "===================="
  Write-Host "WorkDir     : $work"
  Write-Host "Hint        : $hint"
  Write-Host "Base(under) : $base   (第2引数)"
  Write-Host "Top(over)   : $top    (WorkDir自動選択)"
  Write-Host "Opacity     : $Opacity"
  Write-Host "Audio(mode) : $audioMode"
  Write-Host "Out         : $out"
  Write-Host "===================="
  Write-Host ""

  Write-Host "ffmpeg 開始..."
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
