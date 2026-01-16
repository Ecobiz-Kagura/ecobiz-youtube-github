# ============================================================
# run5.ps1（完全版）
# ============================================================

param(
  # ---------- STEP 1: charamin ----------
  [string]$SetupScriptPath = ".\11-yakuza-1970.ps1",

  # Mode（epilogue/ghost/silent/twilight/dark/light など拡張可能）
  [string]$Mode = "epilogue",

  # MakeWide は bool（PowerShell 5.1 対応、true/false 明示）
  [bool]$MakeWide = $true,

  [int]$WideFontSize = 20,

  # ---------- STEP 2: overlay ----------
  [ValidateSet("dark","light")]
  [string]$OverlayTheme = "dark",

  [ValidateSet("left","right","center")]
  [string]$OverlayFrom  = "left",

  # ---------- STEP 3: add_BGM_* ----------
  [string]$BgmTheme   = "dark",
  [double]$FadeInSec  = 1.0,
  [double]$FadeOutSec = 1.0,
  [double]$Volume     = 0.85,

  # Mode -> 対応スクリプト
  [hashtable]$BgmScriptByMode = @{
    "epilogue" = ".\add_BGM_epilogue.ps1"
    "ghost"    = ".\add_BGM_ghost.ps1"
    "silent"   = ".\add_BGM_silent.ps1"
    "twilight" = ".\add_BGM_twilight.ps1"
    "dark"     = ".\add_BGM_dark.ps1"
    "light"    = ".\add_BGM_light.ps1"
  },

  # ---------- STEP 4: uploader ----------
  [string]$UploaderMode = "yakuza",

  # Mp4Path は省略可 → 最新 *.ccs と同名の *.mp4 を期待名として設定
  [string]$Mp4Path,

  # 実行前に確認
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

# -------- Mp4Path 自動設定 ----------
function Resolve-Mp4PathFromLatestCcs() {
  $ccs = Get-ChildItem -File -ErrorAction SilentlyContinue *.ccs |
         Sort-Object LastWriteTime -Descending |
         Select-Object -First 1

  if (-not $ccs) {
    throw "ERROR: Mp4Path omitted AND no .ccs found in current directory."
  }

  $base = [IO.Path]::GetFileNameWithoutExtension($ccs.Name)
  $mp4  = Join-Path (Get-Location) ($base + ".mp4")

  Write-Host "[INFO] CCS found: $($ccs.Name)"
  Write-Host "[INFO] Expected MP4: $mp4 (may not exist yet)"
  return $mp4
}

# Mp4Path 未指定時は CCS から生成する（mp4存在不要）
if (-not $Mp4Path) {
  $Mp4Path = Resolve-Mp4PathFromLatestCcs
}

# -------- 実行前の確認 --------
if ($ConfirmBeforeRun) {
  Write-Host ""
  Write-Host "====================================="
  Write-Host "実行パラメータ（確認してください）"
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

Exec 1 "charamin-overlay3" $step1

# ============================================================
# STEP 2: overlay11.ps1
# ============================================================
Exec 2 "overlay11" @(
  "pwsh","-NoProfile","-ExecutionPolicy","Bypass","-File",
  ".\overlay11.ps1",
  "-OverlayTheme", $OverlayTheme,
  "-OverlayFrom",  $OverlayFrom
)

# ============================================================
# STEP 3: add_BGM_*（Modeに応じて実行）
# ============================================================
if ($BgmScriptByMode.ContainsKey($Mode)) {

  $bgmScript = $BgmScriptByMode[$Mode]

  if (Test-Path $bgmScript) {
    Exec 3 ("add_BGM ($Mode)") @(
      "pwsh","-NoProfile","-ExecutionPolicy","Bypass","-File",
      $bgmScript,
      "-BgmTheme",  $BgmTheme,
      "-FadeInSec", "$FadeInSec",
      "-FadeOutSec","$FadeOutSec",
      "-Volume",    "$Volume"
    )
  } else {
    Write-Host "[STEP 3] add_BGM script not found → SKIP ($bgmScript)"
  }

} else {
  Write-Host "[STEP 3] No add_BGM mapping for Mode='$Mode' → SKIP"
}

# ============================================================
# STEP 3.9: *_bgm.mp4 → *.mp4 へコピー（アップロード直前）
# ============================================================
$bgmMp4 = [IO.Path]::ChangeExtension($Mp4Path, $null) + "_bgm.mp4"

if (Test-Path $bgmMp4) {
  Write-Host "[INFO] Copy: $bgmMp4 → $Mp4Path"
  Copy-Item -Force $bgmMp4 $Mp4Path
} else {
  Write-Host "[INFO] No *_bgm.mp4 found → Skip copy"
}

# ============================================================
# STEP 4: uploader11.py（ここで初めてmp4存在確認）
# ============================================================
if (-not (Test-Path $Mp4Path)) {
  throw "ERROR: Expected MP4 not found after processing: $Mp4Path"
}

try {
  Exec 4 "uploader11 (python)" @(
    "python",".\uploader11.py",
    "--mode",$UploaderMode,
    $Mp4Path
  )
}
catch {
  Write-Host "[WARN] python failed → trying py" -ForegroundColor Yellow
  Exec 4 "uploader11 (py)" @(
    "py",".\uploader11.py",
    "--mode",$UploaderMode,
    $Mp4Path
  )
}

Write-Host ""
Write-Host "=== DONE ==="
