# ============================================================
# run9.ps1（完全版）
#  - 起動直後に：カレント直下の最新 *.ccs を確認し、Mp4Path を確定（Mp4Path 省略時）
#  - SkipOverlay 対応
#  - add-BGM-*.ps1（-InputMp4）/ 旧 add_BGM_*.ps1（-BgmTheme 等）を自動判定
#  - *_bgm.mp4 を優先アップロード
#  - 処理時間表示（STEP/TOTAL、異常終了でも finally で TOTAL）
#  - 実行前確認：①パラメータ一覧 + ②実行コマンド一覧 を一気に表示 → y/N
# ============================================================

param(
  # ---------- STEP 1: charamin ----------
  [string]$SetupScriptPath = ".\11-yakuza-1970.ps1",

  # Mode（epilogue/ghost/silent/twilight/dark/light など）
  [string]$Mode = "epilogue",

  # MakeWide は bool（PowerShell 5.1 対応）
  [bool]$MakeWide = $true,

  [int]$WideFontSize = 20,

  # ---------- STEP 2: overlay ----------
  [ValidateSet("dark","light","epilogue")]
  [string]$OverlayTheme = "dark",

  [ValidateSet("left","right","center")]
  [string]$OverlayFrom  = "left",

  # ★ overlay11 を無効化するオプション
  [bool]$SkipOverlay = $false,

  # ---------- STEP 3: add_BGM_* ----------
  [string]$BgmTheme   = "dark",
  [double]$FadeInSec  = 1.0,
  [double]$FadeOutSec = 1.0,
  [double]$Volume     = 0.85,

  # ★実ファイル名に合わせてハイフン版を既定に（存在しなければ SKIP 表示）
  [hashtable]$BgmScriptByMode = @{
    "epilogue" = ".\add-BGM-epilogue.ps1"
    "ghost"    = ".\add-BGM-ghost.ps1"
    "silent"   = ".\add-BGM-silent.ps1"
    "twilight" = ".\add-BGM-twilight.ps1"
    "dark"     = ".\add-BGM-dark.ps1"
    "light"    = ".\add-BGM-light.ps1"
  },

  # ---------- STEP 4: uploader ----------
  [string]$UploaderMode = "yakuza",

  # Mp4Path は省略可（省略時は最新 ccs から確定）
  [string]$Mp4Path,

  # 実行前確認
  [bool]$ConfirmBeforeRun = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

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

# STEPごとの計測用関数
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

  if (-not $ccs) {
    throw "ERROR: Mp4Path omitted AND no .ccs found in current directory."
  }

  $base = [IO.Path]::GetFileNameWithoutExtension($ccs.Name)
  $mp4  = Join-Path (Get-Location) ($base + ".mp4")

  Write-Host "[INFO] CCS found (latest): $($ccs.Name)"
  Write-Host "[INFO] Mp4Path fixed from CCS: $mp4"
  return $mp4
}

# -------- add_BGM 呼び出し引数の自動判定 ----------
# - add-BGM-*.ps1 : param([string]$InputMp4) を持つなら -InputMp4 を渡す
# - 旧 add_BGM_*.ps1 : BgmTheme/FadeInSec/FadeOutSec/Volume を持つなら存在するものだけ渡す
function Get-BgmArgs([string]$ScriptPath, [string]$Mp4PathToUse) {
  $text = Get-Content -Raw -ErrorAction Stop $ScriptPath

  $args = @()

  $hasInputMp4  = ($text -match '(?is)\$InputMp4\b')
  $hasBgmTheme  = ($text -match '(?is)\$BgmTheme\b')
  $hasFadeInSec = ($text -match '(?is)\$FadeInSec\b')
  $hasFadeOutSec= ($text -match '(?is)\$FadeOutSec\b')
  $hasVolume    = ($text -match '(?is)\$Volume\b')

  if ($hasInputMp4) {
    $args += @("-InputMp4", $Mp4PathToUse)
    return ,$args
  }

  if ($hasBgmTheme)  { $args += @("-BgmTheme",  "$BgmTheme") }
  if ($hasFadeInSec) { $args += @("-FadeInSec", "$FadeInSec") }
  if ($hasFadeOutSec){ $args += @("-FadeOutSec","$FadeOutSec") }
  if ($hasVolume)    { $args += @("-Volume",    "$Volume") }

  return ,$args
}

# ============================================================
# 起動直後に Mp4Path を確定（Mp4Path 省略時は最新 ccs から）
# ============================================================
if (-not $Mp4Path) {
  $Mp4Path = Resolve-Mp4PathFromLatestCcs
}

# ============================================================
# ここからプレビュー（①②）用に、各ステップのコマンド配列を確定
# （Mp4Path が確定しているので、STEP2/STEP3 も確定表示できる）
# ============================================================

# STEP1
$step1 = @(
  "pwsh","-NoProfile","-ExecutionPolicy","Bypass","-File",
  ".\charamin-overlay3.ps1",
  $SetupScriptPath,
  "",
  $Mode,
  "-WideFontSize", "$WideFontSize"
)
if ($MakeWide) { $step1 += "-MakeWide" }

# STEP2（SkipOverlay=false の時だけ実行）
$step2 = @(
  "pwsh","-NoProfile","-ExecutionPolicy","Bypass","-File",
  ".\overlay11.ps1",
  "-BackgroundVideoPath", $Mp4Path,
  "-OverlayTheme", $OverlayTheme,
  "-OverlayFrom",  $OverlayFrom
)

# STEP3（Mode に応じて）
$bgmScript = $null
$step3 = $null
if ($BgmScriptByMode.ContainsKey($Mode)) {
  $bgmScript = $BgmScriptByMode[$Mode]
  if (Test-Path $bgmScript) {
    $bgmArgs = Get-BgmArgs $bgmScript $Mp4Path
    $step3 = @(
      "pwsh","-NoProfile","-ExecutionPolicy","Bypass","-File",
      $bgmScript
    ) + $bgmArgs
  }
}

# STEP4（アップロード対象は実行時に確定するが、プレビューでは条件表示）
$uploadPreview = "<*_bgm.mp4 があればそれを、無ければ *.mp4 をアップロード>"
$step4_preview = @("python",".\uploader11.py","--mode",$UploaderMode,$uploadPreview)

# ============================================================
# 実行前確認：①パラメータ一覧 + ②実行コマンド一覧 を一気に表示 → y/N
# ============================================================
if ($ConfirmBeforeRun) {

  Write-Host ""
  Write-Host "====================================="
  Write-Host "実行パラメータ（確認）"
  Write-Host "====================================="
  $PSBoundParameters.GetEnumerator() | ForEach-Object {
    Write-Host ("{0} = {1}" -f $_.Key, $_.Value)
  }

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

  if ($BgmScriptByMode.ContainsKey($Mode)) {
    if ($bgmScript -and (Test-Path $bgmScript) -and $step3) {
      Write-Host "STEP3: $bgmScript"
      Write-Host ("  > {0}" -f ($step3 -join " "))
    } else {
      if ($bgmScript) {
        Write-Host "STEP3: add_BGM → SKIP (not found: $bgmScript)"
      } else {
        Write-Host "STEP3: add_BGM → SKIP (empty script path)"
      }
    }
  } else {
    Write-Host "STEP3: add_BGM → SKIP (no mapping for Mode='$Mode')"
  }

  Write-Host "STEP4: uploader11.py"
  Write-Host ("  > {0}" -f ($step4_preview -join " "))

  Write-Host ""
  $ansAll = Read-Host "これらのコマンドを実行しますか？ (y/N)"
  if ($ansAll -ne "y" -and $ansAll -ne "Y") {
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

  # ============================================================
  # STEP1 実行
  # ============================================================
  Measure-Step 1 "charamin-overlay3" {
    Exec 1 "charamin-overlay3" $step1
  }

  # ============================================================
  # STEP 2 実行
  # ============================================================
  if ($SkipOverlay) {
    Write-Host "[STEP 2] overlay11 SKIPPED (SkipOverlay=$SkipOverlay)"
  } else {
    Measure-Step 2 "overlay11" {
      Exec 2 "overlay11" $step2
    }
  }

  # ============================================================
  # STEP 3 実行
  # ============================================================
  if ($BgmScriptByMode.ContainsKey($Mode)) {
    if ($bgmScript -and (Test-Path $bgmScript) -and $step3) {
      Measure-Step 3 ("add_BGM ($Mode)") {
        Exec 3 ("add_BGM ($Mode)") $step3
      }
    } else {
      if ($bgmScript) {
        Write-Host "[STEP 3] add_BGM script not found → SKIP ($bgmScript)"
      } else {
        Write-Host "[STEP 3] add_BGM mapping exists but script path empty → SKIP"
      }
    }
  } else {
    Write-Host "[STEP 3] No add_BGM mapping for Mode='$Mode' → SKIP"
  }

  # ============================================================
  # STEP 3.9: *_bgm.mp4 → *.mp4（コピーは維持）
  # ============================================================
  $bgmMp4 = [IO.Path]::ChangeExtension($Mp4Path, $null) + "_bgm.mp4"

  Measure-Step 39 "3.9 copy *_bgm.mp4 -> *.mp4" {
    if (Test-Path $bgmMp4) {
      Write-Host "[INFO] Copy: $bgmMp4 → $Mp4Path"
      Copy-Item -Force $bgmMp4 $Mp4Path
    } else {
      Write-Host "[INFO] No *_bgm.mp4 found → Skip copy"
    }
  }

  # ============================================================
  # UPLOAD TARGET: *_bgm.mp4 を優先
  # ============================================================
  $UploadMp4Path = $Mp4Path
  Measure-Step 40 "select upload target" {
    if (Test-Path $bgmMp4) {
      $UploadMp4Path = $bgmMp4
      Write-Host "[INFO] Upload target: $UploadMp4Path"
    } else {
      Write-Host "[INFO] Upload target: $UploadMp4Path (no *_bgm.mp4)"
    }
  }

  # ============================================================
  # STEP 4: uploader11.py（確定した UploadMp4Path を使う）
  # ============================================================
  if (-not (Test-Path $UploadMp4Path)) {
    throw "ERROR: Expected MP4 not found: $UploadMp4Path"
  }

  Measure-Step 4 "uploader11" {
    try {
      Exec 4 "uploader11 (python)" @(
        "python",".\uploader11.py",
        "--mode",$UploaderMode,
        $UploadMp4Path
      )
    }
    catch {
      Write-Host "[WARN] python failed → trying py" -ForegroundColor Yellow
      Exec 4 "uploader11 (py)" @(
        "py",".\uploader11.py",
        "--mode",$UploaderMode,
        $UploadMp4Path
      )
    }
  }

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
