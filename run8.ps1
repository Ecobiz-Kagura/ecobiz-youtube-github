# ============================================================
# run5.ps1（完全版：SkipOverlay + *_bgm.mp4 Upload + 処理時間表示）
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

  # Mp4Path は省略可
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

# -------- Mp4Path 解決用 ----------
function Resolve-Mp4PathFromLatestCcs() {
  $ccs = Get-ChildItem -File -ErrorAction SilentlyContinue *.ccs |
         Sort-Object LastWriteTime -Descending |
         Select-Object -First 1

  if (-not $ccs) {
    throw "ERROR: Mp4Path omitted AND no .ccs found."
  }

  $base = [IO.Path]::GetFileNameWithoutExtension($ccs.Name)
  $mp4  = Join-Path (Get-Location) ($base + ".mp4")

  Write-Host "[INFO] CCS found: $($ccs.Name)"
  Write-Host "[INFO] Expected MP4: $mp4"
  return $mp4
}

# Mp4Path が省略されたかを記録
$Mp4PathWasOmitted = -not $Mp4Path

# -------- 実行前の確認 --------
if ($ConfirmBeforeRun) {
  Write-Host ""
  Write-Host "====================================="
  Write-Host "実行パラメータ（確認）"
  Write-Host "====================================="
  $PSBoundParameters.GetEnumerator() | ForEach-Object {
    Write-Host ("{0} = {1}" -f $_.Key, $_.Value)
  }
  Write-Host ""

  $ans = Read-Host "Execute? (y/N)"
  if ($ans -ne "y" -and $ans -ne "Y") {
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
  # STEP 1: charamin-overlay3.ps1
  # ============================================================
  $step1 = @(
    "pwsh","-NoProfile","-ExecutionPolicy","Bypass","-File",
    ".\charamin-overlay3.ps1",
    $SetupScriptPath,
    "",
    $Mode,
    "-WideFontSize", "$WideFontSize"
  )
  if ($MakeWide) { $step1 += "-MakeWide" }

  Measure-Step 1 "charamin-overlay3" {
    Exec 1 "charamin-overlay3" $step1
  }

  # STEP1 後に Mp4Path を確定
  if ($Mp4PathWasOmitted) {
    $Mp4Path = Resolve-Mp4PathFromLatestCcs
  }

  # ============================================================
  # STEP 2: overlay11.ps1（SkipOverlay 対応）
  # ============================================================
  if ($SkipOverlay) {
    Write-Host "[STEP 2] overlay11 SKIPPED (SkipOverlay=$SkipOverlay)"
  } else {
    Measure-Step 2 "overlay11" {
      Exec 2 "overlay11" @(
        "pwsh","-NoProfile","-ExecutionPolicy","Bypass","-File",
        ".\overlay11.ps1",
        "-BackgroundVideoPath", $Mp4Path,
        "-OverlayTheme", $OverlayTheme,
        "-OverlayFrom",  $OverlayFrom
      )
    }
  }

  # ============================================================
  # STEP 3: add_BGM_*（Mode に応じて）
  # ============================================================
  if ($BgmScriptByMode.ContainsKey($Mode)) {
    $bgmScript = $BgmScriptByMode[$Mode]
    if (Test-Path $bgmScript) {
      Measure-Step 3 ("add_BGM ($Mode)") {
        Exec 3 ("add_BGM ($Mode)") @(
          "pwsh","-NoProfile","-ExecutionPolicy","Bypass","-File",
          $bgmScript,
          "-BgmTheme",  $BgmTheme,
          "-FadeInSec", "$FadeInSec",
          "-FadeOutSec","$FadeOutSec",
          "-Volume",    "$Volume"
        )
      }
    } else {
      Write-Host "[STEP 3] add_BGM script not found → SKIP ($bgmScript)"
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
  # STEP 4: uploader11.py
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
