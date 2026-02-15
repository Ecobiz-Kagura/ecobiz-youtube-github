<#
gt5.ps1（完全版 / --prefix 廃止 / 既存 .txt 絶対保護）
- カレントの mp4 全削除（確認）
- TTS自動生成（google_txt2tts_srt_mp4_jp.py）
- OverlayMode=subonly 既定（字幕のみ＝背景が隠れない）
- ASS字幕焼き付け（確実）
- 音声ソース overlay/base
- BGM追加（指定フォルダ直下のみで add-BGM-*.ps1 / add_BGM_*.ps1 を探索）
- ★最終出力名：常に「第1引数TxtFileのベース名.mp4」（BGM後もこの名前に統一）
- ★最終出力名の確認 y/N（確定）
- uploader11.py（任意）
  - -SkipUpload でスキップ（スキップも y/N）
  - ★アップロード実行前に「Python実体パス / uploader実体パス / argv配列 / cmdline 表示 → y/N」
- ★重要：カレント以外を“検索しない”
  - ps1同名mp4は ps1フォルダ直下のみ（再帰なし）
  - BGMスクリプトも BgmScriptDir 直下のみ（再帰なし）
  - 「最新mp4」などはカレント直下のみ

★既存 .txt は絶対に潰さない（上書き禁止）
  - 入力TxtFileは読み取りのみ
  - uploader用の同名 .txt は「存在したら作らない（上書きしない）」

★--prefix は一切渡さない（完全廃止）
  - タイトルへの mode 反映は uploader11.py 側で行う（別パッチ参照）
#>

param(
  [Parameter(Position=0, Mandatory=$true)]
  [string]$TxtFile,

  [Parameter(Position=1, Mandatory=$true)]
  [string]$Ps1File,

  [Parameter(Mandatory=$false)]
  [ValidateSet("subonly","video")]
  [string]$OverlayMode = "subonly",

  [Parameter(Mandatory=$false)]
  [ValidateRange(0.0,1.0)]
  [double]$Alpha = 1.0,

  # （通常は指定不要：最終名は txtベース名.mp4 に統一）
  [Parameter(Mandatory=$false)]
  [string]$OutMp4,

  [Parameter(Mandatory=$false)]
  [string]$PythonExe = "python",

  [Parameter(Mandatory=$false)]
  [string]$TtsPy = ".\google_txt2tts_srt_mp4_jp.py",

  # mp4無ければ自動生成
  [Parameter(Mandatory=$false)]
  [bool]$AutoMakeMp4 = $true,

  [Parameter(Mandatory=$false)]
  [switch]$ForceTts,

  [Parameter(Mandatory=$false)]
  [switch]$SwapLayers,

  [Parameter(Mandatory=$false)]
  [bool]$BurnSub = $true,

  [Parameter(Mandatory=$false)]
  [ValidateSet("overlay","base")]
  [string]$AudioSource = "overlay",

  [Parameter(Mandatory=$false)]
  [ValidateSet("none","epilogue","ghost","dark","light")]
  [string]$BgmTheme = "none",

  [Parameter(Mandatory=$false)]
  [string]$BgmScriptDir = ".",

  [Parameter(Mandatory=$false)]
  [bool]$AdoptBgmOutput = $true,

  [Parameter(Mandatory=$false)]
  [ValidateRange(0,600)]
  [int]$SubMarginLR = 160,

  [Parameter(Mandatory=$false)]
  [ValidateRange(10,240)]
  [int]$SubFontSize = 20,

  [Parameter(Mandatory=$false)]
  [ValidateRange(0,20)]
  [int]$SubOutline = 3,

  [Parameter(Mandatory=$false)]
  [ValidateRange(0,20)]
  [int]$SubShadow = 0,

  [Parameter(Mandatory=$false)]
  [ValidateRange(0,300)]
  [int]$SubMarginV = 40,

  [Parameter(Mandatory=$false)]
  [string]$SubFontName = "MS Gothic",

  [Parameter(Mandatory=$false)]
  [ValidateRange(320,7680)]
  [int]$TargetW = 1920,

  [Parameter(Mandatory=$false)]
  [ValidateRange(240,4320)]
  [int]$TargetH = 1080,

  # uploader
  [Parameter(Mandatory=$false)]
  [string]$UploadMode = "",

  [Parameter(Mandatory=$false)]
  [switch]$SkipUpload,

  [Parameter(Mandatory=$false)]
  [switch]$ConfirmToday,   # uploader側の挙動

  [Parameter(Mandatory=$false)]
  [switch]$UploaderDryRun,

  [Parameter(Mandatory=$false)]
  [switch]$UploaderNoMove,

  [Parameter(Mandatory=$false)]
  [string]$UploaderPy = ".\uploader11.py"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host ("===== gt5.ps1 START {0} =====" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
Write-Host ""

function Fail([string]$msg){ throw "[ERROR] $msg" }
function NowStamp(){ (Get-Date).ToString("yyyyMMdd_HHmmss") }

function Resolve-Existing([string]$p, [string]$label){
  $rp = (Resolve-Path -LiteralPath $p -ErrorAction Stop).Path
  if(!(Test-Path -LiteralPath $rp)){ Fail "$label が存在しません: $rp" }
  return $rp
}

function Find-Ffmpeg(){
  $cmd = Get-Command ffmpeg -ErrorAction SilentlyContinue
  if($null -eq $cmd){ Fail "ffmpeg が PATH にありません。" }
  return $cmd.Source
}

function Find-Python([string]$pythonExe){
  $parts = $pythonExe -split "\s+"
  $exe = $parts[0]
  $cmd = Get-Command $exe -ErrorAction SilentlyContinue
  if($null -eq $cmd){ Fail "Python が見つかりません: $pythonExe" }
  return @{ Source = $cmd.Source; Extra = @($parts | Select-Object -Skip 1) }
}

function QuoteIfNeeded([string]$s){
  if($s -match '\s|&|\(|\)|\^|;|,|=|:|\[|\]'){
    return '"' + ($s -replace '"','\"') + '"'
  }
  return $s
}

function Join-CmdLine([string]$exe, [object[]]$argv){
  $qexe = QuoteIfNeeded $exe
  $qargs = $argv | ForEach-Object { QuoteIfNeeded ([string]$_) }
  return ($qexe + " " + ($qargs -join " ")).Trim()
}

function Esc-ForAssFilter([string]$p){
  $x = $p -replace "\\","/"
  $x = $x -replace ":","\:"
  $x = $x -replace "'","\'"
  return $x
}

function Pick-LatestMp4InDir([string]$dir){
  # ★カレント直下のみ
  $hits = @(Get-ChildItem -LiteralPath $dir -Filter *.mp4 -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
  if($hits.Count -eq 0){ return $null }
  return $hits[0].FullName
}

function Touch-Now([string]$p){
  if(!(Test-Path -LiteralPath $p)){ Fail "Touch対象が見つかりません: $p" }
  (Get-Item -LiteralPath $p).LastWriteTime = (Get-Date)
}

function Build-TtsArgs([string]$ttsAbs, [string]$txtAbs, [string]$pythonExe){
  $pyInfo = Find-Python $pythonExe
  $pySrc = $pyInfo.Source
  $pyExtra = @($pyInfo.Extra)
  $ttsArgs = @()
  $ttsArgs += $pyExtra
  $ttsArgs += @("-X","utf8",$ttsAbs,$txtAbs)
  return @{ PySrc=$pySrc; Args=$ttsArgs; CmdLine=(Join-CmdLine $pySrc $ttsArgs) }
}

function Run-Tts([string]$pythonExe, [string]$ttsPy, [string]$txtAbs){
  $env:PYTHONUTF8 = "1"
  $env:PYTHONIOENCODING = "utf-8"
  try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}
  try { $OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

  $ttsAbs = Resolve-Existing $ttsPy "TtsPy"
  $built = Build-TtsArgs $ttsAbs $txtAbs $pythonExe

  Write-Host "----- STEP: Google TTS mp4 generate -----"
  Write-Host $built.CmdLine
  Write-Host ""

  & $built.PySrc @($built.Args)
  if($LASTEXITCODE -ne 0){
    Fail "Google TTS mp4 生成が失敗しました (exitcode=$LASTEXITCODE)"
  }
}

function To-AssTime([string]$hhmmssmmm){
  if($hhmmssmmm -notmatch '^(\d{2}):(\d{2}):(\d{2}),(\d{3})$'){ return $null }
  $h=[int]$matches[1]; $m=[int]$matches[2]; $s=[int]$matches[3]; $ms=[int]$matches[4]
  $cs = [int]([math]::Floor($ms / 10.0))
  return ("{0}:{1:00}:{2:00}.{3:00}" -f $h,$m,$s,$cs)
}

function Convert-SrtToAss(
  [string]$srtPath,
  [string]$assPath,
  [int]$playResX,
  [int]$playResY,
  [string]$fontName,
  [int]$fontSize,
  [int]$outline,
  [int]$shadow,
  [int]$marginLR,
  [int]$marginV
){
  if(!(Test-Path -LiteralPath $srtPath)){ Fail "SRT が見つかりません: $srtPath" }

  $header = @"
[Script Info]
ScriptType: v4.00+
WrapStyle: 2
ScaledBorderAndShadow: yes
PlayResX: $playResX
PlayResY: $playResY

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,$fontName,$fontSize,&H00FFFFFF,&H000000FF,&H00000000,&H64000000,0,0,0,0,100,100,0,0,1,$outline,$shadow,2,$marginLR,$marginLR,$marginV,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"@

  $lines = Get-Content -LiteralPath $srtPath -Encoding UTF8 -ErrorAction SilentlyContinue
  if($null -eq $lines){ $lines = Get-Content -LiteralPath $srtPath }

  $outEvents = New-Object System.Collections.Generic.List[string]
  $i=0
  while($i -lt $lines.Count){
    $line = ($lines[$i]).Trim()
    if($line -match '^\d+$'){ $i++; continue }

    if($line -match '^(\d{2}:\d{2}:\d{2},\d{3})\s*-->\s*(\d{2}:\d{2}:\d{2},\d{3})'){
      $st = To-AssTime $matches[1]
      $ed = To-AssTime $matches[2]
      if($null -eq $st -or $null -eq $ed){ $i++; continue }
      $i++

      $textParts = New-Object System.Collections.Generic.List[string]
      while($i -lt $lines.Count){
        $t = $lines[$i]
        if([string]::IsNullOrWhiteSpace($t)){ break }
        $t = $t -replace "\r",""
        $t = $t -replace "\\","\\\\"
        $t = $t -replace '\{','｛'
        $t = $t -replace '\}','｝'
        $textParts.Add($t.Trim())
        $i++
      }
      $assText = ($textParts -join "\N")
      $outEvents.Add("Dialogue: 0,$st,$ed,Default,,0,0,0,,$assText")
    }
    $i++
  }

  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($assPath, $header + "`r`n" + ($outEvents -join "`r`n") + "`r`n", $utf8NoBom)
}

function Resolve-BgmScript([string]$theme, [string]$dir){
  if($theme -eq "none"){ return $null }
  $dirAbs = (Resolve-Path -LiteralPath $dir -ErrorAction Stop).Path

  # ★直下のみ（再帰しない）
  $candidates = @(
    (Join-Path $dirAbs ("add-BGM-{0}.ps1" -f $theme)),
    (Join-Path $dirAbs ("add_BGM_{0}.ps1" -f $theme)),
    (Join-Path $dirAbs ("add-bgm-{0}.ps1" -f $theme)),
    (Join-Path $dirAbs ("add_bgm_{0}.ps1" -f $theme))
  )
  foreach($c in $candidates){
    if(Test-Path -LiteralPath $c){ return $c }
  }
  return $null
}

function Run-Bgm([string]$bgmScript, [string]$inMp4, [bool]$adoptOutput){
  $cwd = (Get-Location).Path
  $before = Pick-LatestMp4InDir $cwd

  Write-Host "----- STEP: BGM ADD -----"
  Write-Host (Join-CmdLine $bgmScript @($inMp4))
  Write-Host ""

  & $bgmScript $inMp4
  if($LASTEXITCODE -ne 0){
    Fail "BGM 追加が失敗しました。exitcode=$LASTEXITCODE"
  }

  if(-not $adoptOutput){
    return $inMp4
  }

  # ★カレント直下の最新mp4だけを見る
  $after = Pick-LatestMp4InDir $cwd
  if($null -ne $after -and ($null -eq $before -or $after -ne $before)){
    return $after
  }
  return $inMp4
}

# =====================================================
# uploader: ★実行形の完全可視化（python/uploader実体パス + argv配列）
# ★--prefix は一切渡さない
# =====================================================
function Build-UploaderCmd(
  [string]$pythonExe,
  [string]$uploaderPy,
  [string]$mode,
  [string]$mp4Path,
  [switch]$confirmToday,
  [switch]$dryRun,
  [switch]$noMove
){
  $uAbs = Resolve-Existing $uploaderPy "UploaderPy"
  $pyInfo = Find-Python $pythonExe
  $pySrc  = $pyInfo.Source
  $pyExtra = @($pyInfo.Extra)

  $argsAll = @()
  $argsAll += $pyExtra
  $argsAll += @("-X","utf8",$uAbs)
  $argsAll += @("--mode",$mode)
  $argsAll += @("--mp4",$mp4Path)

  if($confirmToday){ $argsAll += "--confirm_today" }
  if($dryRun){       $argsAll += "--dry_run" }
  if($noMove){       $argsAll += "--no_move" }

  return @{
    PySrc            = $pySrc
    UploaderResolved = $uAbs
    ArgsAll          = $argsAll
    CmdLine          = (Join-CmdLine $pySrc $argsAll)
  }
}

function Run-Uploader(
  [string]$pythonExe,
  [string]$uploaderPy,
  [string]$mode,
  [string]$mp4Path,
  [switch]$confirmToday,
  [switch]$dryRun,
  [switch]$noMove
){
  if([string]::IsNullOrWhiteSpace($mode)){ return }
  if(!(Test-Path -LiteralPath $mp4Path)){ Fail "uploader 用 mp4 が見つかりません: $mp4Path" }

  $env:PYTHONUTF8 = "1"
  $env:PYTHONIOENCODING = "utf-8"
  try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}
  try { $OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

  $built = Build-UploaderCmd $pythonExe $uploaderPy $mode $mp4Path `
    -confirmToday:$confirmToday -dryRun:$dryRun -noMove:$noMove

  Write-Host ""
  Write-Host "=== アップロード実行前（コマンド確認）==="
  Write-Host ("PythonResolved  : {0}" -f $built.PySrc)
  Write-Host ("UploaderResolved: {0}" -f $built.UploaderResolved)
  Write-Host ""
  Write-Host "CMDLINE:"
  Write-Host $built.CmdLine
  Write-Host ""
  Write-Host "ARGV (PowerShell が & に渡す配列):"
  for($i=0; $i -lt $built.ArgsAll.Count; $i++){
    Write-Host ("  [{0}] {1}" -f $i, $built.ArgsAll[$i])
  }
  Write-Host "========================================"
  $ans = Read-Host "このコマンドでアップロードしますか？ (y/N)"
  if($ans -ne "y" -and $ans -ne "Y"){
    Write-Host "アップロードをキャンセルしました。"
    return
  }

  Write-Host "----- STEP: uploader -----"
  Write-Host $built.CmdLine
  Write-Host ""

  & $built.PySrc @($built.ArgsAll)
  if($LASTEXITCODE -ne 0){
    Fail "uploader が失敗しました (exitcode=$LASTEXITCODE)"
  }
}

# =====================================================
# 0) カレントの mp4 全削除（確認）
# =====================================================
# =====================================================
# 0) カレント配下すべての mp4 全削除（再帰 / 確認付き）
# =====================================================
$cwd = (Get-Location).Path

# ★再帰で取得
$mp4s = @(Get-ChildItem -LiteralPath $cwd -Filter *.mp4 -File -Recurse -ErrorAction SilentlyContinue)

if($mp4s.Count -gt 0){
  Write-Host ""
  Write-Host "=== 注意：カレント配下すべての mp4 を削除します（再帰） ==="
  foreach($m in $mp4s){
    Write-Host " - $($m.FullName)"
  }
  Write-Host "=============================================================="
  $ansDel = Read-Host "本当に削除しますか？ (y/N)"

  if($ansDel -eq "y" -or $ansDel -eq "Y"){
    foreach($m in $mp4s){
      Remove-Item -LiteralPath $m.FullName -Force -ErrorAction SilentlyContinue
    }
    Write-Host "mp4 をすべて削除しました。"
  } else {
    Write-Host "mp4 削除をキャンセルしました。"
  }
} else {
  Write-Host "削除対象 mp4 はありません。"
}

# =====================================================
# 入力解決（探索はしない）
# =====================================================
$txtAbs = Resolve-Existing $TxtFile "TxtFile"
$ps1Abs = Resolve-Existing $Ps1File "Ps1File"

# =====================================================
# ★ Ps1File を実行（他は変更しない）
# =====================================================
Write-Host ""
Write-Host "----- STEP: Ps1File EXECUTE -----"
Write-Host $ps1Abs
Write-Host ""

& $ps1Abs
if($LASTEXITCODE -ne 0){
  Fail "Ps1File の実行が失敗しました (exitcode=$LASTEXITCODE)"
}

$txtMp4 = [System.IO.Path]::ChangeExtension($txtAbs, ".mp4")
$txtSrt = [System.IO.Path]::ChangeExtension($txtAbs, ".srt")
$txtAss = [System.IO.Path]::ChangeExtension($txtAbs, ".ass")

# 背景（ps1同名mp4：ps1フォルダ直下のみ）
$ps1Dir  = Split-Path -Parent $ps1Abs
$ps1Stem = [System.IO.Path]::GetFileNameWithoutExtension($ps1Abs)
$ps1Mp4Cand = Join-Path $cwd ($ps1Stem + ".mp4")
if(!(Test-Path -LiteralPath $ps1Mp4Cand)){
  Fail "ps1 と同名の mp4 が見つかりません（ps1フォルダ直下のみ）: $ps1Mp4Cand"
}
$ps1Mp4 = $ps1Mp4Cand

# TTS 実行要否
$ttsWillRun = $false
if($ForceTts){
  $ttsWillRun = $true
} elseif(!(Test-Path -LiteralPath $txtMp4)) {
  if($AutoMakeMp4){ $ttsWillRun = $true }
}

# 一時出力名
if([string]::IsNullOrWhiteSpace($OutMp4)){
  $OutMp4 = Join-Path $cwd ("overlay2_{0}.mp4" -f (NowStamp))
}else{
  $outDir = Split-Path -Parent $OutMp4
  if([string]::IsNullOrWhiteSpace($outDir)){ $outDir = $cwd }
  $outDir = (Resolve-Path -LiteralPath $outDir).Path
  $OutMp4 = Join-Path $outDir (Split-Path -Leaf $OutMp4)
}

# レイヤ
if($SwapLayers){
  $baseMp4    = $txtMp4
  $overlayMp4 = $ps1Mp4
}else{
  $baseMp4    = $ps1Mp4
  $overlayMp4 = $txtMp4
}

# BGMスクリプト
$bgmScript = $null
if($BgmTheme -ne "none"){
  $bgmScript = Resolve-BgmScript $BgmTheme $BgmScriptDir
  if($null -eq $bgmScript){
    Fail "BGM スクリプトが見つかりません（指定dir直下のみ）: theme=$BgmTheme dir=$BgmScriptDir"
  }
}

# 音声 map
$audioMap = if($AudioSource -eq "overlay"){ "1:a?" } else { "0:a?" }

# ★最終名（確定名の予定）：txtStem.mp4（カレント）
$txtStem = [System.IO.Path]::GetFileNameWithoutExtension($txtAbs)
$plannedFinal = Join-Path $cwd ($txtStem + ".mp4")

# ffmpeg / filter
$ffmpeg = Find-Ffmpeg

$baseNorm =
  "[0:v]scale=${TargetW}:${TargetH}:force_original_aspect_ratio=increase," +
  "crop=${TargetW}:${TargetH}[base0]"

if($OverlayMode -eq "video"){
  $ovNorm = if($Alpha -lt 1.0){
    "[1:v]scale=${TargetW}:${TargetH}:force_original_aspect_ratio=increase," +
    "crop=${TargetW}:${TargetH},format=rgba," +
    "colorchannelmixer=aa=${Alpha}[ov0]"
  } else {
    "[1:v]scale=${TargetW}:${TargetH}:force_original_aspect_ratio=increase," +
    "crop=${TargetW}:${TargetH}[ov0]"
  }
  $vfCore = $baseNorm + ";" + $ovNorm + ";" + "[base0][ov0]overlay=0:0[pre]"
}else{
  $vfCore = $baseNorm + ";" + "[base0]null[pre]"
}

# =====================================================
# 実行前表示（ありったけ）
# =====================================================
Write-Host ""
Write-Host "==================================================="
Write-Host "=== 実行内容（生成＋アップロード）ありったけ ==="
Write-Host "CWD           : $cwd"
Write-Host "Txt           : $txtAbs"
Write-Host "Ps1           : $ps1Abs"
Write-Host "OverlayMode   : $OverlayMode"
Write-Host "SwapLayers    : $SwapLayers"
Write-Host "背景(Base)    : $baseMp4"
Write-Host "前景(Overlay) : $overlayMp4"
Write-Host "Alpha         : $Alpha"
Write-Host "字幕(BurnSub) : $BurnSub"
Write-Host "TargetWH      : ${TargetW}x${TargetH}"
Write-Host "AudioSource   : $AudioSource  (map $audioMap)"
Write-Host "BgmTheme      : $BgmTheme"
if($BgmTheme -ne "none"){ Write-Host "BgmScript     : $bgmScript" }
Write-Host "UploadMode    : $UploadMode"
Write-Host "SkipUpload    : $SkipUpload"
Write-Host "一時出力(Out) : $OutMp4"
Write-Host "最終出力(予定): $plannedFinal"
Write-Host "TTS           : " -NoNewline
if($ttsWillRun){ Write-Host "RUN" } else { Write-Host "SKIP" }
if($BurnSub){
  Write-Host "SRT           : $txtSrt"
  Write-Host "ASS           : $txtAss"
  Write-Host "SubFontName   : $SubFontName"
  Write-Host "SubFontSize   : $SubFontSize"
  Write-Host "SubOutline    : $SubOutline"
  Write-Host "SubShadow     : $SubShadow"
  Write-Host "SubMarginLR   : $SubMarginLR"
  Write-Host "SubMarginV    : $SubMarginV"
}
if(Test-Path -LiteralPath $plannedFinal){
  Write-Host ""
  Write-Host "=== 注意：最終出力が既に存在します ==="
  Write-Host "既存ファイルは上書きされます:"
  Write-Host "  $plannedFinal"
  Write-Host "======================================"
}
Write-Host "==================================================="
Write-Host ""

$ansGo = Read-Host "この内容で「生成」を実行しますか？ (y/N)"
if($ansGo -ne "y" -and $ansGo -ne "Y"){
  Write-Host "キャンセルしました。"
  exit
}

# =====================================================
# 実行（TTS → ass → ffmpeg → rename → bgm → rename）
# =====================================================
if($ttsWillRun){
  Run-Tts $PythonExe $TtsPy $txtAbs
}

if(!(Test-Path -LiteralPath $txtMp4)){
  Fail "txt と同名の mp4 が見つかりません（生成後も存在しない）: $txtMp4"
}
if($BurnSub -and !(Test-Path -LiteralPath $txtSrt)){
  Fail "字幕焼き付け指定ですが SRT が見つかりません（TTS後も存在しない）: $txtSrt"
}

if($BurnSub){
  Convert-SrtToAss `
    -srtPath $txtSrt `
    -assPath $txtAss `
    -playResX $TargetW `
    -playResY $TargetH `
    -fontName $SubFontName `
    -fontSize $SubFontSize `
    -outline $SubOutline `
    -shadow $SubShadow `
    -marginLR $SubMarginLR `
    -marginV $SubMarginV
}

$vf = if($BurnSub){
  $assEsc = Esc-ForAssFilter $txtAss
  $vfCore + ";[pre]ass='$assEsc',setsar=1[v]"
}else{
  $vfCore + ";[pre]setsar=1[v]"
}

$ffArgs = @(
  "-y",
  "-i", $baseMp4,
  "-i", $overlayMp4,
  "-filter_complex", $vf,
  "-map", "[v]",
  "-map", $audioMap,
  "-c:v", "libx264",
  "-pix_fmt", "yuv420p",
  "-c:a", "aac",
  "-b:a", "192k",
  "-shortest",
  $OutMp4
)

Write-Host ""
Write-Host "----- STEP: ffmpeg -----"
Write-Host (Join-CmdLine $ffmpeg $ffArgs)
Write-Host ""

$sw = [Diagnostics.Stopwatch]::StartNew()
& $ffmpeg @ffArgs
if($LASTEXITCODE -ne 0){
  Fail "ffmpeg が失敗しました。exitcode=$LASTEXITCODE"
}

# 一時Out → plannedFinal に統一（上書き）
$finalOut = $plannedFinal
if([System.IO.Path]::GetFullPath($OutMp4) -ine [System.IO.Path]::GetFullPath($finalOut)){
  if(Test-Path -LiteralPath $finalOut){
    Remove-Item -LiteralPath $finalOut -Force -ErrorAction SilentlyContinue
  }
  Move-Item -LiteralPath $OutMp4 -Destination $finalOut -Force
}
Touch-Now $finalOut

# BGM（任意）→ 最終名に統一
if($BgmTheme -ne "none"){
  $bgmOut = Run-Bgm $bgmScript $finalOut $AdoptBgmOutput

  if([System.IO.Path]::GetFullPath($bgmOut) -ine [System.IO.Path]::GetFullPath($finalOut)){
    if(!(Test-Path -LiteralPath $bgmOut)){ Fail "BGM後の mp4 が見つかりません: $bgmOut" }
    Remove-Item -LiteralPath $finalOut -Force -ErrorAction SilentlyContinue
    Move-Item -LiteralPath $bgmOut -Destination $finalOut -Force
  }
  Touch-Now $finalOut
}

# 最終出力確認（y/N）
Write-Host ""
Write-Host "=== 最終出力確認 ==="
Write-Host "FinalOut      : $finalOut"
Write-Host ("LastWriteTime : {0}" -f (Get-Item -LiteralPath $finalOut).LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss"))
Write-Host "===================="
$ansFinal = Read-Host "この最終出力名で確定しますか？ (y/N)"
if($ansFinal -ne "y" -and $ansFinal -ne "Y"){
  $sw.Stop()
  Write-Host "最終出力の確定をキャンセルしました（生成は完了済み）。"
  Write-Host ("完了: {0}" -f $finalOut)
  Write-Host ("Elapsed: {0:hh\:mm\:ss\.fff}" -f $sw.Elapsed)
  Write-Host ("===== gt5.ps1 END {0} =====" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
  exit
}

# =====================================================
# uploader（任意）
# - SkipUpload でも y/N（スキップ確認）
# - 実行するなら「python/uploader実体パス + argv配列 + cmdline 表示 → y/N」
# - ★既存 .txt は絶対に上書きしない
# =====================================================
if($SkipUpload){

  $wouldRun = $null
  if(-not [string]::IsNullOrWhiteSpace($UploadMode)){
    $wouldRun = Build-UploaderCmd $PythonExe $UploaderPy $UploadMode $finalOut `
      -confirmToday:$ConfirmToday -dryRun:$UploaderDryRun -noMove:$UploaderNoMove
  }

  Write-Host ""
  Write-Host "=== アップロードスキップ確認 ==="
  Write-Host "UploadMode : $UploadMode"
  Write-Host "MP4       : $finalOut"
  if($wouldRun -ne $null){
    Write-Host "（参考）本来のコマンド:"
    Write-Host ("PythonResolved  : {0}" -f $wouldRun.PySrc)
    Write-Host ("UploaderResolved: {0}" -f $wouldRun.UploaderResolved)
    Write-Host $wouldRun.CmdLine
  } else {
    Write-Host "（参考）UploadMode が空のためコマンドは生成しません。"
  }
  Write-Host "=========================="
  $ansSkip = Read-Host "アップロードをスキップしますか？ (y/N)"
  if($ansSkip -ne "y" -and $ansSkip -ne "Y"){
    Write-Host "スキップを取り消しました。UploadMode が指定されていればアップロードへ進みます。"
    if([string]::IsNullOrWhiteSpace($UploadMode)){
      Write-Host "UploadMode が空のため、アップロードは実行できません。"
    } else {
      Run-Uploader $PythonExe $UploaderPy $UploadMode $finalOut `
        -confirmToday:$ConfirmToday -dryRun:$UploaderDryRun -noMove:$UploaderNoMove
    }
  } else {
    Write-Host "SkipUpload: アップロードをスキップしました。"
  }

} elseif(-not [string]::IsNullOrWhiteSpace($UploadMode)){

  # タイトル誘導txt：mp4と同名.txt をカレントに作る（検索なし）
  # ★既存 .txt は絶対に潰さない：存在したら作らない（上書き禁止）
  $titleLine = (Split-Path -Leaf $txtAbs)
  $metaTxt = [System.IO.Path]::ChangeExtension($finalOut, ".txt")
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

  if(Test-Path -LiteralPath $metaTxt){
    Write-Host ""
    Write-Host "=== 注意：既存 .txt 保護 ==="
    Write-Host "既に存在するため、作成しません（上書き禁止）:"
    Write-Host "  $metaTxt"
    Write-Host "=========================="
  } else {
    [System.IO.File]::WriteAllText($metaTxt, ($titleLine + "`r`n"), $utf8NoBom)
    Write-Host ("TitleTxt を作成しました: {0}" -f $metaTxt)
  }

  Write-Host ""
  Write-Host "=== アップロード確認（詳細）==="
  Write-Host "UploadMode    : $UploadMode"
  Write-Host "MP4           : $finalOut"
  Write-Host "TitleTxt      : $metaTxt"
  Write-Host "TitleLine     : $titleLine"
  Write-Host "DryRun        : $UploaderDryRun"
  Write-Host "NoMove        : $UploaderNoMove"
  Write-Host "ConfirmToday  : $ConfirmToday"
  Write-Host "==============================="
  $ansUp = Read-Host "この内容でアップロードへ進みますか？ (y/N)"
  if($ansUp -ne "y" -and $ansUp -ne "Y"){
    Write-Host "アップロードをキャンセルしました（生成は完了済み）。"
  } else {
    Run-Uploader $PythonExe $UploaderPy $UploadMode $finalOut `
      -confirmToday:$ConfirmToday -dryRun:$UploaderDryRun -noMove:$UploaderNoMove
  }
}

$sw.Stop()
Write-Host ""
Write-Host ("完了: {0}" -f $finalOut)
Write-Host ("Elapsed: {0:hh\:mm\:ss\.fff}" -f $sw.Elapsed)
Write-Host ("===== gt5.ps1 END {0} =====" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
