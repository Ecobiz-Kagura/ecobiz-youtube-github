# ============================================================
# cevio-long-10.ps1（完全版：cevio-short-9.ps1 と引数体系を統一）
#
# 使い方（統一）:
#   .\cevio-long-10.ps1 <InputPs1> <Theme> -BgmVolume 0.7 -MainVolume 1.30 -VoiceGain 1.40 -SkipUpload
#
# 統一方針:
#  - Position0: InputPs1（= SetupScriptPath）
#  - Position1: Theme（= Mode。twilight/ghost...）
#  - -UploadMode（= UploaderMode）
#  - -SkipUpload
#  - -BgmVolume / -MainVolume / -VoiceGain（下位スクリプトが対応していれば渡す。未対応は自動フォールバック）
#
# 既存互換:
#  - SetupScriptPath, Mode, UploaderMode, Volume も引き続き使える（Alias/同期）
#  - ConfirmBeforeRun, SkipOverlay, PreDeleteMp4 など既存維持
#
# ★追加:
#  - uploader mode をスイッチで切替可能（-kasyu / -kankyou など）
#    * スイッチが1つだけ指定されたら UploadMode を上書き
#    * 複数スイッチ指定はエラー（事故防止）
#  - ★すべての y/N を 10秒無入力で自動Y（解除）に統一
# ============================================================

param(
  # ★統一：cevio-short と同じ「位置0 = 入力ps1」
  [Parameter(Position=0, Mandatory=$true)]
  [Alias("SetupScriptPath")]
  [string]$InputPs1,

  # ★統一：cevio-short と同じ「位置1 = テーマ（= Mode）」
  [Parameter(Position=1, Mandatory=$false)]
  [ValidateSet("none","epilogue","ghost","silent","twilight","dark","light")]
  [Alias("BgmTheme","Theme","Mode")]
  [string]$RunTheme = "epilogue",

  # ---------- STEP 1: charamin ----------
  [bool]$MakeWide = $true,
  [int]$WideFontSize = 20,

  # ---------- STEP 2: overlay ----------
  [ValidateSet("dark","light","epilogue")]
  [string]$OverlayTheme = "dark",

  [ValidateSet("left","right","center")]
  [string]$OverlayFrom  = "left",

  [bool]$SkipOverlay = $false,

  # ---------- STEP 3: add_BGM_* ----------
  # ★統一：cevio-short と同名の音量引数
  [double]$BgmVolume  = 0.85,   # run10 の旧 Volume(0.85) に合わせた既定
  [double]$MainVolume = 1.00,
  [double]$VoiceGain  = 1.00,

  # 旧引数互換（残す）
  [double]$FadeInSec  = 1.0,
  [double]$FadeOutSec = 1.0,

  # ★旧 Volume 互換（指定されたら BgmVolume に同期）
  [Alias("Volume")]
  [double]$LegacyVolume = 0.85,

  # add_BGM スクリプト割当
  [hashtable]$BgmScriptByMode = @{
    "epilogue" = ".\add-BGM-epilogue.ps1"
    "ghost"    = ".\add-BGM-ghost.ps1"
    "silent"   = ".\add-BGM-silent.ps1"
    "twilight" = ".\add-BGM-twilight.ps1"
    "dark"     = ".\add-BGM-dark.ps1"
    "light"    = ".\add-BGM-light.ps1"
  },

  # ---------- STEP 4: uploader ----------
  # ★統一：cevio-short と同名 UploadMode（文字列指定は維持）
  [Alias("UploaderMode")]
  [string]$UploadMode = "yakuza",

  # ★追加：mode をスイッチで切替（必要なものだけ使えばOK）
  [switch]$yakuza,
  [switch]$kankyou,
  [switch]$kasyu,
  [switch]$joyuu,
  [switch]$rekishi,
  [switch]$rakugo,

  # ★統一：cevio-short と同名 SkipUpload
  [switch]$SkipUpload,

  # Mp4Path は省略可（省略時は最新 ccs から確定）
  [string]$Mp4Path,

  # 起動直後に mp4 を削除（y/N、10秒無入力で自動Y）
  [bool]$PreDeleteMp4 = $false,

  # 実行前確認（y/N、10秒無入力で自動Y）
  [bool]$ConfirmBeforeRun = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Fail([string]$msg){ throw "[ERROR] $msg" }

function Clamp([double]$x, [double]$min, [double]$max){
  if([double]::IsNaN($x) -or [double]::IsInfinity($x)){ return $min }
  if($x -lt $min){ return $min }
  if($x -gt $max){ return $max }
  return $x
}

# ============================================================
# ★すべての y/N を 10秒無入力で自動Y に統一する入力関数
#   - 戻り値: "y" or "n"
# ============================================================
function Read-YesNoTimeoutDefaultY([string]$prompt, [int]$timeoutSec = 10){
  Write-Host -NoNewline $prompt
  $start = Get-Date
  $buf = ""

  while($true){
    while([Console]::KeyAvailable){
      $k = [Console]::ReadKey($true)

      if($k.Key -eq "Enter"){
        Write-Host ""
        break
      }
      if($k.Key -eq "Backspace"){
        if($buf.Length -gt 0){
          $buf = $buf.Substring(0, $buf.Length - 1)
          Write-Host -NoNewline "`b `b"
        }
        continue
      }
      $ch = $k.KeyChar
      if($ch -ne [char]0){
        $buf += $ch
        Write-Host -NoNewline $ch
      }
    }

    if($buf -ne $null -and $buf -match '^(?i)\s*[yn]\s*$'){
      $ans = $buf.Trim().ToLower()
      if($ans -eq "y" -or $ans -eq "n"){ return $ans }
    }

    if(((Get-Date) - $start).TotalSeconds -ge $timeoutSec){
      Write-Host ""
      Write-Host "(auto) y"
      return "y"
    }
    Start-Sleep -Milliseconds 50
  }

  if([string]::IsNullOrWhiteSpace($buf)){
    Write-Host "(auto) y"
    return "y"
  }
  $t = $buf.Trim().ToLower()
  if($t -eq "y" -or $t -eq "n"){ return $t }

  Write-Host "(auto) y"
  return "y"
}

# ---- 統一・互換の同期 ----
if($PSBoundParameters.ContainsKey("LegacyVolume") -and -not $PSBoundParameters.ContainsKey("BgmVolume")){
  $BgmVolume = $LegacyVolume
}

# 音量は安全側に丸める
$BgmVolume  = Clamp $BgmVolume  0.0 2.0
$MainVolume = Clamp $MainVolume 0.0 2.0
$VoiceGain  = Clamp $VoiceGain  0.0 4.0

# Theme=none は「BGMなし」の意
$Mode = $RunTheme

# ============================================================
# uploader mode: スイッチ切替
# ============================================================
$modeSwitchMap = @{
  "yakuza"  = $yakuza
  "kankyou" = $kankyou
  "kasyu"   = $kasyu
  "joyuu"   = $joyuu
  "rekishi" = $rekishi
  "rakugo"  = $rakugo
}

$selectedModes = @($modeSwitchMap.Keys | Where-Object { $modeSwitchMap[$_] })

if($selectedModes.Count -gt 1){
  throw ("[ERROR] uploader mode スイッチは1つだけ指定してください: {0}" -f ($selectedModes -join ", "))
}
if($selectedModes.Count -eq 1){
  $UploadMode = $selectedModes[0]
}

# カレントをスクリプトの場所に移動
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

# -------- 共通関数 ----------
function Exec([int]$Step, [string]$Title, [string[]]$Cmd) {
  Write-Host ""
  Write-Host "========================="
  Write-Host ("[STEP {0}] {1}" -f $Step, $Title)
  Write-Host ("  > {0}" -f ($Cmd -join ' '))
  Write-Host "========================="
  & $Cmd[0] @($Cmd[1..($Cmd.Count-1)])
  if ($LASTEXITCODE -ne 0) {
    throw ("Command failed (exit={0}): STEP {1} {2}" -f $LASTEXITCODE, $Step, $Title)
  }
}

function Measure-Step([int]$StepNum, [string]$Title, [scriptblock]$Block) {
  $s = Get-Date
  Write-Host ""
  Write-Host "----- STEP $StepNum : $Title START ($s) -----"
  & $Block
  $e = Get-Date
  $span = $e - $s
  Write-Host "----- STEP $StepNum : $Title END   ($e) -----"
  Write-Host ("  処理時間: {0} 秒  ({1})" -f ([int]$span.TotalSeconds), $span)
  Write-Host ""
}

# -------- Mp4Path 解決用（最新 ccs から） ----------
function Resolve-Mp4PathFromLatestCcs() {
  $ccs = Get-ChildItem -File -ErrorAction SilentlyContinue *.ccs |
         Sort-Object LastWriteTime -Descending |
         Select-Object -First 1
  if (-not $ccs) { throw "ERROR: Mp4Path omitted AND no .ccs found in current directory." }

  $base = [IO.Path]::GetFileNameWithoutExtension($ccs.Name)
  $mp4  = Join-Path (Get-Location) ($base + ".mp4")

  Write-Host "[INFO] CCS found (latest): $($ccs.Name)"
  Write-Host "[INFO] Mp4Path fixed from CCS: $mp4"
  return $mp4
}

# -------- mp4削除（y/N、10秒無入力で自動Y） ----------
function Confirm-AndDeleteMp4InCwd_Exclude {
  param([string]$ExcludeFullPath, [int]$timeoutSec = 10)

  $cwd0 = (Get-Location).Path
  $excludeNorm = $null
  if($ExcludeFullPath){
    try { $excludeNorm = (Resolve-Path -LiteralPath $ExcludeFullPath -ErrorAction Stop).Path.ToLower() }
    catch { $excludeNorm = $ExcludeFullPath.ToLower() }
  }

  $mp4s = Get-ChildItem -LiteralPath $cwd0 -File -Filter "*.mp4" -ErrorAction SilentlyContinue |
    Where-Object { if(-not $excludeNorm){ $true } else { $_.FullName.ToLower() -ne $excludeNorm } }

  if(-not $mp4s -or $mp4s.Count -eq 0){
    Write-Host "[INFO] 削除対象の mp4 はありません（Mp4Path除外後）: $cwd0"
    return
  }

  Write-Host ""
  Write-Host "====================================================="
  Write-Host "  事前処理：カレントの mp4 削除"
  Write-Host "====================================================="
  Write-Host ("対象: {0}" -f $cwd0)
  if($ExcludeFullPath){ Write-Host ("除外: {0}" -f $ExcludeFullPath) }
  Write-Host ("件数: {0}" -f $mp4s.Count)

  $showN = [Math]::Min(20, [int]$mp4s.Count)
  for($i=0; $i -lt $showN; $i++){
    Write-Host ("  - {0}" -f $mp4s[$i].Name)
  }
  if($mp4s.Count -gt $showN){
    Write-Host ("  ...（他 {0} 件）" -f ($mp4s.Count - $showN))
  }

  $ans = Read-YesNoTimeoutDefaultY ("削除しますか？ (y/N) [10秒で自動Y]: ") $timeoutSec
  if($ans -ne "y"){
    Write-Host "[INFO] mp4 削除はスキップしました。"
    return
  }

  foreach($f in $mp4s){
    Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
  }
  Write-Host "[INFO] mp4 を削除しました。"
}

# -------- add_BGM 呼び出し引数の自動判定（統一音量も渡す） ----------
function Get-BgmArgsUnified([string]$ScriptPath, [string]$Mp4PathToUse) {
  $text = Get-Content -Raw -ErrorAction Stop $ScriptPath
  $args = @()

  $hasInputMp4   = ($text -match '(?is)\$InputMp4\b')
  $hasBgmTheme   = ($text -match '(?is)\$BgmTheme\b')
  $hasFadeInSec  = ($text -match '(?is)\$FadeInSec\b')
  $hasFadeOutSec = ($text -match '(?is)\$FadeOutSec\b')

  $hasVolume     = ($text -match '(?is)\$Volume\b')
  $hasBgmVolume  = ($text -match '(?is)\$BgmVolume\b')
  $hasMainVolume = ($text -match '(?is)\$MainVolume\b')

  if ($hasInputMp4) {
    $args += @("-InputMp4", $Mp4PathToUse)
    if($hasBgmVolume){  $args += @("-BgmVolume",  "$BgmVolume") }
    if($hasMainVolume){ $args += @("-MainVolume", "$MainVolume") }
    if($hasVolume -and -not $hasBgmVolume){ $args += @("-Volume", "$BgmVolume") }
    return ,$args
  }

  if ($hasBgmTheme)   { $args += @("-BgmTheme",  "$Mode") }
  if ($hasFadeInSec)  { $args += @("-FadeInSec", "$FadeInSec") }
  if ($hasFadeOutSec) { $args += @("-FadeOutSec","$FadeOutSec") }

  if($hasBgmVolume){  $args += @("-BgmVolume",  "$BgmVolume") }
  if($hasMainVolume){ $args += @("-MainVolume", "$MainVolume") }
  if($hasVolume -and -not $hasBgmVolume){ $args += @("-Volume", "$BgmVolume") }

  return ,$args
}

# -------- overlay11 呼び出し（VoiceGain を“対応していれば”渡す） ----------
function Get-OverlayArgsUnified([string]$OverlayScriptPath, [string]$Mp4PathToUse) {
  $args = @(
    "-BackgroundVideoPath", $Mp4PathToUse,
    "-OverlayTheme", $OverlayTheme,
    "-OverlayFrom",  $OverlayFrom
  )

  try{
    $txt = Get-Content -Raw -ErrorAction Stop $OverlayScriptPath
    $hasVoiceGain = ($txt -match '(?is)\$VoiceGain\b') -or ($txt -match '(?is)VoiceGain\b')
    if($hasVoiceGain){
      $args += @("-VoiceGain", "$VoiceGain")
    }
  } catch { }

  return ,$args
}

# ============================================================
# 起動直後に Mp4Path を確定（Mp4Path 省略時は最新 ccs から）
# ============================================================
if (-not $Mp4Path) {
  $Mp4Path = Resolve-Mp4PathFromLatestCcs
}

# PreDeleteMp4（10秒無入力で自動Y）
if($PreDeleteMp4){
  Confirm-AndDeleteMp4InCwd_Exclude -ExcludeFullPath $Mp4Path -timeoutSec 10
}

# ============================================================
# ここからプレビュー用に各ステップのコマンド配列を確定
# ============================================================

# STEP1: charamin-overlay3.ps1
$step1 = @(
  "pwsh","-NoProfile","-ExecutionPolicy","Bypass","-File",
  ".\charamin-overlay3.ps1",
  $InputPs1,
  "",
  $Mode,
  "-WideFontSize", "$WideFontSize"
)
if ($MakeWide) { $step1 += "-MakeWide" }

# STEP2: overlay11.ps1
$overlayScript = ".\overlay11.ps1"
$step2 = @("pwsh","-NoProfile","-ExecutionPolicy","Bypass","-File", $overlayScript) +
         (Get-OverlayArgsUnified $overlayScript $Mp4Path)

# STEP3: add_BGM
$bgmScript = $null
$step3 = $null
if($Mode -ne "none" -and $BgmScriptByMode.ContainsKey($Mode)){
  $bgmScript = $BgmScriptByMode[$Mode]
  if(Test-Path $bgmScript){
    $bgmArgs = Get-BgmArgsUnified $bgmScript $Mp4Path
    $step3 = @("pwsh","-NoProfile","-ExecutionPolicy","Bypass","-File", $bgmScript) + $bgmArgs
  }
}

# STEP4 preview
$uploadPreview = "<*_bgm.mp4 があればそれを、無ければ *.mp4 をアップロード>"
$step4_preview = @("python",".\uploader11.py","--mode",$UploadMode,$uploadPreview)

# ============================================================
# 実行前確認（10秒無入力で自動Y）
# ============================================================
if ($ConfirmBeforeRun) {

  Write-Host ""
  Write-Host "====================================="
  Write-Host "実行パラメータ（確認）"
  Write-Host "====================================="
  Write-Host ("InputPs1      = {0}" -f $InputPs1)
  Write-Host ("Mode(Theme)   = {0}" -f $Mode)
  Write-Host ("UploadMode    = {0}" -f $UploadMode)
  Write-Host ("SkipUpload    = {0}" -f ([bool]$SkipUpload))
  Write-Host ("BgmVolume     = {0}" -f $BgmVolume)
  Write-Host ("MainVolume    = {0}" -f $MainVolume)
  Write-Host ("VoiceGain     = {0}" -f $VoiceGain)
  Write-Host ("Mp4Path       = {0}" -f $Mp4Path)
  Write-Host ("PreDeleteMp4  = {0}" -f $PreDeleteMp4)
  Write-Host ("SkipOverlay   = {0}" -f $SkipOverlay)

  Write-Host ""
  Write-Host "====================================="
  Write-Host "実行コマンド（確認）"
  Write-Host "====================================="

  Write-Host "STEP1: charamin-overlay3.ps1"
  Write-Host ("  > {0}" -f ($step1 -join " "))

  if ($SkipOverlay) {
    Write-Host "STEP2: overlay11.ps1 → SKIPPED (SkipOverlay=$SkipOverlay)"
  } else {
    Write-Host "STEP2: overlay11.ps1"
    Write-Host ("  > {0}" -f ($step2 -join " "))
  }

  if ($Mode -eq "none") {
    Write-Host "STEP3: add_BGM → SKIP (Mode='none')"
  } elseif ($BgmScriptByMode.ContainsKey($Mode)) {
    if ($bgmScript -and (Test-Path $bgmScript) -and $step3) {
      Write-Host "STEP3: $bgmScript"
      Write-Host ("  > {0}" -f ($step3 -join " "))
    } else {
      Write-Host "STEP3: add_BGM → SKIP (not found: $bgmScript)"
    }
  } else {
    Write-Host "STEP3: add_BGM → SKIP (no mapping for Mode='$Mode')"
  }

  if($SkipUpload){
    Write-Host "STEP4: uploader11.py → SKIPPED (SkipUpload)"
  } else {
    Write-Host "STEP4: uploader11.py"
    Write-Host ("  > {0}" -f ($step4_preview -join " "))
  }

  Write-Host ""
  $ansAll = Read-YesNoTimeoutDefaultY "これらのコマンドを実行しますか？ (y/N) [10秒で自動Y]: " 10
  if ($ansAll -ne "y") {
    Write-Host "キャンセルされました。"
    exit
  }
}

Write-Host ""
Write-Host "[INFO] 実行開始..."
Write-Host ""

# ===== 全体タイマー開始（確認待ち時間は含めない）=====
$TotalStart = Get-Date

try {

  # STEP1
  Measure-Step 1 "charamin-overlay3" {
    Exec 1 "charamin-overlay3" $step1
  }

  # STEP2
  if ($SkipOverlay) {
    Write-Host "[STEP 2] overlay11 SKIPPED (SkipOverlay=$SkipOverlay)"
  } else {
    Measure-Step 2 "overlay11" {
      Exec 2 "overlay11" $step2
    }
  }

  # STEP3
  if ($Mode -eq "none") {
    Write-Host "[STEP 3] add_BGM SKIPPED (Mode='none')"
  } elseif ($BgmScriptByMode.ContainsKey($Mode)) {
    if ($bgmScript -and (Test-Path $bgmScript) -and $step3) {
      Measure-Step 3 ("add_BGM ($Mode)") {
        Exec 3 ("add_BGM ($Mode)") $step3
      }
    } else {
      Write-Host "[STEP 3] add_BGM script not found → SKIP ($bgmScript)"
    }
  } else {
    Write-Host "[STEP 3] No add_BGM mapping for Mode='$Mode' → SKIP"
  }

  # STEP 3.9: *_bgm.mp4 → *.mp4（コピーは維持）
  $bgmMp4 = [IO.Path]::ChangeExtension($Mp4Path, $null) + "_bgm.mp4"
  Measure-Step 39 "3.9 copy *_bgm.mp4 -> *.mp4" {
    if (Test-Path $bgmMp4) {
      Write-Host "[INFO] Copy: $bgmMp4 → $Mp4Path"
      Copy-Item -Force $bgmMp4 $Mp4Path
    } else {
      Write-Host "[INFO] No *_bgm.mp4 found → Skip copy"
    }
  }

  # upload target
  $UploadMp4Path = $Mp4Path
  Measure-Step 40 "select upload target" {
    if (Test-Path $bgmMp4) {
      $UploadMp4Path = $bgmMp4
      Write-Host "[INFO] Upload target: $UploadMp4Path"
    } else {
      Write-Host "[INFO] Upload target: $UploadMp4Path (no *_bgm.mp4)"
    }
  }

  # STEP4 uploader（SkipUpload対応）
  if($SkipUpload){
    Write-Host "[STEP 4] uploader11 SKIPPED (SkipUpload)"
  } else {
    if (-not (Test-Path $UploadMp4Path)) {
      throw "ERROR: Expected MP4 not found: $UploadMp4Path"
    }

    Measure-Step 4 "uploader11" {
      try {
        Exec 4 "uploader11 (python)" @(
          "python",".\uploader11.py",
          "--mode",$UploadMode,
          $UploadMp4Path
        )
      }
      catch {
        Write-Host "[WARN] python failed → trying py" -ForegroundColor Yellow
        Exec 4 "uploader11 (py)" @(
          "py",".\uploader11.py",
          "--mode",$UploadMode,
          $UploadMp4Path
        )
      }
    }
  }

  # done 移動（失敗しても落とさない）
  Write-Host "ccsファイルとwavファイルをdoneに移動"
  mv *.ccs ./done/ -ErrorAction SilentlyContinue
  mv *.wav ./done/ -ErrorAction SilentlyContinue
  mv *.mp4 ./done/ -ErrorAction SilentlyContinue

  Write-Host ""
  Write-Host "=== DONE ==="
}
finally {
  $TotalEnd  = Get-Date
  $TotalSpan = $TotalEnd - $TotalStart

  Write-Host ""
  Write-Host "================ TOTAL ================"
  Write-Host "開始時刻 : $TotalStart"
  Write-Host "終了時刻 : $TotalEnd"
  Write-Host ("総処理時間 : {0} 秒 ({1})" -f ([int]$TotalSpan.TotalSeconds), $TotalSpan)
  Write-Host "======================================"
}
