#requires -Version 5.1
[CmdletBinding()]
param(
  # charamin 用 SetupScript（例: .\11-yakuza-1970.ps1）
  [Parameter(Mandatory=$true)]
  [string]$SetupScript,

  # 実行対象（必要なら差し替え）
  [string]$CharaminScript = ".\charamin-overlay3.ps1",
  [string]$OverlayScript  = ".\overlay11.ps1",
  [string]$UploaderPy     = ".\uploader11.py",

  # charamin 側
  [ValidateSet("epilogue","twilight","silent")]
  [string]$Mode = "epilogue",

  [switch]$MakeWide,
  [int]$WideFontSize = 20,

  # ★ユーザー操作としてはBGMを連想する名前にする（内部では overlay11 の -OverlayTheme に渡す）
  [ValidateSet("dark","light")]
  [string]$BgmTheme = "dark",

  # ★省略したら overlay11.ps1 を呼ばない（＝overlayスキップ）
  #    指定された場合のみ overlay11.ps1 を呼び出す
  [ValidateSet("left","right","center","random")]
  [string]$OverlayFrom,

  # uploader 側
  [ValidateSet("yakuza","joyuu","kankyou","none")]
  [string]$UploadMode = "yakuza",

  # overlay11 に追加で渡したい引数（例: -AddBGM など）
  [string[]]$OverlayExtraArgs = @(),

  # 実行しないで表示だけ
  [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-File([string]$p,[string]$label){
  if (-not (Test-Path -LiteralPath $p)) { throw "Not found ($label): $p" }
}

function Stamp([string]$msg){
  $t = (Get-Date).ToString("HH:mm:ss")
  Write-Host ("[{0}] {1}" -f $t, $msg)
}

function Run-Step {
  param(
    [Parameter(Mandatory=$true)][string]$Title,
    [Parameter(Mandatory=$true)][string]$File,
    [Parameter(Mandatory=$true)][string[]]$Args
  )

  Stamp $Title
  Stamp ("  > {0} {1}" -f $File, ($Args -join " "))

  if ($WhatIf) {
    Stamp "  (WhatIf) skip"
    return
  }

  $p = Start-Process -FilePath $File -ArgumentList $Args -NoNewWindow -PassThru -Wait
  if ($p.ExitCode -ne 0) { throw ("{0} failed (exit={1})" -f $Title, $p.ExitCode) }

  Stamp ($Title + " OK")
}

function Get-Mp4List([string]$dir){
  Get-ChildItem -LiteralPath $dir -File -Filter "*.mp4" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -ExpandProperty FullName
}

function Detect-NewOrLatestMp4([string[]]$before,[string[]]$after){
  # 1) 新規追加を優先
  $newMp4 = Compare-Object $before $after |
    Where-Object SideIndicator -eq "=>" |
    Select-Object -ExpandProperty InputObject |
    Sort-Object { (Get-Item $_).LastWriteTime } -Descending |
    Select-Object -First 1

  if ($newMp4) { return $newMp4 }

  # 2) 同名更新など差分が取れないケース：最新を採用
  return ($after | Select-Object -First 1)
}

# ---- 正規化・存在確認 ----
$SetupScript    = (Resolve-Path -LiteralPath $SetupScript).Path
$CharaminScript = (Resolve-Path -LiteralPath $CharaminScript).Path
$OverlayScript  = (Resolve-Path -LiteralPath $OverlayScript).Path
$UploaderPy     = (Resolve-Path -LiteralPath $UploaderPy).Path

Assert-File $SetupScript    "SetupScript"
Assert-File $CharaminScript "CharaminScript"
Assert-File $OverlayScript  "OverlayScript"
Assert-File $UploaderPy     "UploaderPy"

$workDir = Split-Path -Parent $SetupScript
Stamp ("workDir: {0}" -f $workDir)

Push-Location $workDir
try {
  # 実行前の mp4 一覧
  $beforeMp4 = Get-Mp4List $workDir

  # STEP1: charamin-overlay3.ps1 <SetupScript> "" <Mode> [-MakeWide] [-WideFontSize N]
  $charaminArgs = @(
    "-NoProfile","-ExecutionPolicy","Bypass","-File",$CharaminScript,
    $SetupScript,
    "",
    $Mode
  )
  if ($MakeWide) { $charaminArgs += "-MakeWide" }
  if ($WideFontSize -gt 0) { $charaminArgs += @("-WideFontSize", $WideFontSize.ToString()) }

  Run-Step -Title "STEP1 charamin-overlay3" -File "pwsh" -Args $charaminArgs

  # STEP1 後の mp4 検出（overlay を呼ばない場合のアップロード対象にもなる）
  $afterStep1 = Get-Mp4List $workDir
  $mp4AfterStep1 = Detect-NewOrLatestMp4 -before $beforeMp4 -after $afterStep1
  if (-not $mp4AfterStep1) { throw "STEP1 後の mp4 が見つかりません" }
  Stamp ("detected mp4 after STEP1: {0}" -f $mp4AfterStep1)

  $uploadTarget = $mp4AfterStep1

  # STEP2: overlay11（OverlayFrom が指定された場合のみ）
  if ($PSBoundParameters.ContainsKey("OverlayFrom")) {

    # overlay 実行前一覧
    $beforeStep2 = $afterStep1

    # ★BgmTheme を overlay11 の -OverlayTheme に渡す（引数名はBGM連想、実体は従来通り）
    $overlayArgs = @(
      "-NoProfile","-ExecutionPolicy","Bypass","-File",$OverlayScript,
      "-OverlayTheme",$BgmTheme,
      "-OverlayFrom",$OverlayFrom
    ) + $OverlayExtraArgs

    Run-Step -Title "STEP2 overlay11" -File "pwsh" -Args $overlayArgs

    # overlay 後の mp4 を再検出（これをアップロード対象にする）
    $afterStep2 = Get-Mp4List $workDir
    $mp4AfterStep2 = Detect-NewOrLatestMp4 -before $beforeStep2 -after $afterStep2
    if (-not $mp4AfterStep2) { throw "STEP2 後の mp4 が見つかりません" }
    Stamp ("detected mp4 after STEP2: {0}" -f $mp4AfterStep2)

    $uploadTarget = $mp4AfterStep2

  } else {
    Stamp "STEP2 overlay11 skipped (OverlayFrom not specified)"
  }

  # STEP3: uploader
  Stamp ("upload target: {0}" -f $uploadTarget)
  Run-Step -Title "STEP3 uploader11" -File "python" -Args @($UploaderPy,"--mode",$UploadMode,$uploadTarget)

  Stamp "ALL DONE"
}
finally {
  Pop-Location
}
