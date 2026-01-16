# ============================================================
# run-yakuza-pipeline.ps1（完全版：引数 + CCS/CSSからMp4Path推定（存在不要） + 実行前y/N）
# ============================================================

param(
  # ---------- STEP1: charamin ----------
  [string]$SetupScriptPath = ".\11-yakuza-1970.ps1",
  [ValidateSet("epilogue","normal")]
  [string]$Mode = "epilogue",
  [switch]$MakeWide,
  [int]$WideFontSize = 20,

  # ---------- STEP2: overlay ----------
  [ValidateSet("dark","light")]
  [string]$OverlayTheme = "dark",
  [ValidateSet("left","right","center")]
  [string]$OverlayFrom  = "left",

  # ---------- STEP3: uploader ----------
  [string]$UploaderMode = "yakuza",

  # mp4（省略時：最新の *.ccs / *.css のベース名 + .mp4 を「期待出力」として推定）
  [string]$Mp4Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# スクリプトのある場所で実行（相対パス前提）
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

function Exec([string]$Title, [string[]]$Cmd) {
  Write-Host ""
  Write-Host "========================="
  Write-Host "[RUN] $Title"
  Write-Host "  > $($Cmd -join ' ')"
  Write-Host "========================="
  & $Cmd[0] @($Cmd[1..($Cmd.Count-1)])
  if ($LASTEXITCODE -ne 0) {
    throw "Command failed (exit=$LASTEXITCODE): $Title"
  }
}

function Resolve-ExpectedMp4FromCcsCss() {
  $cand = @()
  $cand += Get-ChildItem -File -ErrorAction SilentlyContinue *.ccs
  $cand += Get-ChildItem -File -ErrorAction SilentlyContinue *.css

  if (-not $cand -or $cand.Count -eq 0) {
    throw "ERROR: Mp4Path omitted AND no .ccs/.css found in current directory."
  }

  $src = $cand | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  Write-Host "[INFO] Found CCS/CSS: $($src.Name)"

  $base = [IO.Path]::GetFileNameWithoutExtension($src.Name)

  # ★存在しない前提なので「期待出力ファイル名」を組み立てるだけ
  $expected = Join-Path (Get-Location) ($base + ".mp4")
  Write-Host "[INFO] Expected MP4 (may not exist yet): $([IO.Path]::GetFileName($expected))"
  return $expected
}

# ============================================================
# Mp4Path 未指定 → CCS/CSS から「期待される mp4 名」を推定（存在チェックしない）
# ============================================================
if (-not $Mp4Path) {
  $Mp4Path = Resolve-ExpectedMp4FromCcsCss
}

# ============================================================
# ★ 実行前にパラメータ一覧を表示して確認（y/N）
# ============================================================
Write-Host ""
Write-Host "====================================="
Write-Host "実行するパラメータ内容（確認してください）"
Write-Host "====================================="
Write-Host ("SetupScriptPath = {0}" -f $SetupScriptPath)
Write-Host ("Mode           = {0}" -f $Mode)
Write-Host ("MakeWide       = {0}" -f ([bool]$MakeWide))
Write-Host ("WideFontSize   = {0}" -f $WideFontSize)
Write-Host ("OverlayTheme   = {0}" -f $OverlayTheme)
Write-Host ("OverlayFrom    = {0}" -f $OverlayFrom)
Write-Host ("UploaderMode   = {0}" -f $UploaderMode)
Write-Host ("Mp4Path        = {0}" -f $Mp4Path)
Write-Host "-------------------------------------"
Write-Host "※ Mp4Path は「最終的に出来上がるはずの mp4」を指します（今は無くてもOK）。"
Write-Host ""

$answer = Read-Host "Execute? (y/N)"
if ($answer -ne "y" -and $answer -ne "Y") {
  Write-Host "キャンセルされました。"
  exit
}

Write-Host ""
Write-Host "[INFO] 確認済み → 実行を開始します..."
Write-Host ""

# ============================================================
# STEP 1: charamin-overlay3.ps1
# ============================================================
$charaminArgs = @(
  "pwsh","-NoProfile","-ExecutionPolicy","Bypass","-File",
  ".\charamin-overlay3.ps1",
  $SetupScriptPath,
  "",
  $Mode,
  "-WideFontSize", "$WideFontSize"
)
if ($MakeWide) { $charaminArgs += "-MakeWide" }

Exec "charamin-overlay3" $charaminArgs

# ============================================================
# STEP 2: overlay11.ps1
# ============================================================
Exec "overlay11" @(
  "pwsh","-NoProfile","-ExecutionPolicy","Bypass","-File",
  ".\overlay11.ps1",
  "-OverlayTheme", $OverlayTheme,
  "-OverlayFrom",  $OverlayFrom
)

# ============================================================
# STEP 3: uploader11.py（ここで初めて存在チェック）
# ============================================================
if (-not (Test-Path $Mp4Path)) {
  throw "ERROR: Expected MP4 not found after processing: $Mp4Path"
}

try {
  Exec "uploader11 (python)" @(
    "python",".\uploader11.py",
    "--mode",$UploaderMode,
    $Mp4Path
  )
}
catch {
  Write-Host "[WARN] python 失敗 → py で再試行" -ForegroundColor Yellow
  Exec "uploader11 (py)" @(
    "py",".\uploader11.py",
    "--mode",$UploaderMode,
    $Mp4Path
  )
}

Write-Host ""
Write-Host "=== DONE ==="
