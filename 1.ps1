# encoding: UTF-8
param(
  [Parameter(Mandatory=$true)][string]$SetupScriptPath,
  [Parameter(Mandatory=$true)][string]$TextPath,

  # ★省略不可：BGM モード
  [Parameter(Mandatory=$true)]
  [ValidateSet("epilogue","twilight","silent")]
  [string]$Mode,

  # ★省略不可：アップロード種別
  [Parameter(Mandatory=$true)]
  [ValidateSet("joyuu","none")]
  [string]$Upload
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# =========================
# 実行時間計測
# =========================
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$startedAt = Get-Date

function Assert-File([string]$p){
  if (-not (Test-Path -LiteralPath $p)) { throw ("Not found: {0}" -f $p) }
}
function Stamp([string]$msg){
  $t = (Get-Date).ToString("HH:mm:ss")
  Write-Host ("[{0}] {1}" -f $t, $msg)
}

# ===== 後片付け設定 =====
$CleanupExts = @(".srt",".mp3",".wav",".mp4")
$DeleteOutputMp4 = $false   # 最終成果物MP4も消すなら $true

# 後で finally でも参照する
$outMp4 = $null

try {
  # =========================
  # 動画自動起動ブロック
  # =========================
  function ii { param([Parameter(ValueFromPipeline=$true, Position=0)][string]$Path)
    if ($Path -match '\.(mp4|mkv|mov|webm)$') { Stamp ("[blocked ii] {0}" -f $Path); return }
    Microsoft.PowerShell.Management\Invoke-Item @PSBoundParameters
  }
  function Invoke-Item { param([Parameter(ValueFromPipeline=$true, Position=0)][string]$Path)
    if ($Path -match '\.(mp4|mkv|mov|webm)$') { Stamp ("[blocked Invoke-Item] {0}" -f $Path); return }
    Microsoft.PowerShell.Management\Invoke-Item @PSBoundParameters
  }
  function Start-Process {
    param([Parameter(Position=0)][string]$FilePath,[string[]]$ArgumentList,[switch]$NoNewWindow,[switch]$Wait,[string]$WorkingDirectory)
    if ($FilePath -match '\.(mp4|mkv|mov|webm)$') { Stamp ("[blocked Start-Process] {0}" -f $FilePath); return }
    Microsoft.PowerShell.Management\Start-Process @PSBoundParameters
  }
  function explorer { param([Parameter(Position=0)][string]$Path)
    if ($Path -match '\.(mp4|mkv|mov|webm)$') { Stamp ("[blocked explorer] {0}" -f $Path); return }
    & "$env:WINDIR\explorer.exe" $Path
  }
  function cmd { param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Args)
    $joined = ($Args -join ' ')
    if ($joined -match '(?i)^\s*/c\s+start(\s|$)' -and $joined -match '\.(mp4|mkv|mov|webm)\b') {
      Stamp ("[blocked cmd start] {0}" -f $joined); return
    }
    & "$env:ComSpec" @Args
  }

  # =========================
  # 入力チェック
  # =========================
  Assert-File $SetupScriptPath
  Assert-File $TextPath

  $SetupScriptPath = (Resolve-Path $SetupScriptPath).Path
  $TextPath        = (Resolve-Path $TextPath).Path

  $txtLeaf = [IO.Path]::GetFileName($TextPath)
  $isShort = ($txtLeaf -match '(?i)short')

  # =========================
  # TTS / overlay / BGM 切替
  # =========================
  $TtsPy = if ($isShort) { ".\google_txt2tts_srt_mp4_jp_short.py" }
           else          { ".\google_txt2tts_srt_mp4_jp.py" }
  Assert-File $TtsPy

  $OverlayPs1 = if ($isShort) { ".\overlay3s.ps1" }
                else          { ".\overlay3.ps1" }
  Assert-File $OverlayPs1

  switch ($Mode) {
    "epilogue" { $BgmPs1 = ".\add-BGM-epilogue.ps1" }
    "twilight" { $BgmPs1 = ".\add-BGM-twilight.ps1" }
    "silent"   { $BgmPs1 = ".\add-BGM-silent.ps1" }
  }
  Assert-File $BgmPs1

  # uploader（joyuu のときだけ使う）
  if ($Upload -eq "joyuu") {
    Assert-File ".\uploader10-joyuu.py"
  }

  # =========================
  # 出力 MP4（txt と同名）
  # =========================
  $txtBase = [IO.Path]::GetFileNameWithoutExtension($TextPath)
  $txtDir  = Split-Path -Parent $TextPath
  $outMp4  = Join-Path $txtDir ($txtBase + ".mp4")

  # =========================
  # setup 実行
  # =========================
  Stamp "=== SETUP ==="
  & $SetupScriptPath

  # =========================
  # overlay 素材推定
  # =========================
  $setupBase = [IO.Path]::GetFileNameWithoutExtension($SetupScriptPath)
  $cand1 = Join-Path (Split-Path -Parent $SetupScriptPath) ($setupBase + ".mp4")

  if (Test-Path -LiteralPath $cand1) {
    $overlayMp4 = (Resolve-Path $cand1).Path
  } else {
    $pool = Get-ChildItem -LiteralPath $txtDir -File -Filter *.mp4 -ErrorAction SilentlyContinue
    if (-not $pool -or $pool.Count -eq 0) {
      throw ("overlay mp4 not found. tried: {0} ; also no *.mp4 in txt dir: {1}" -f $cand1, $txtDir)
    }
    $overlayMp4 = ($pool | Get-Random).FullName
  }

  # =========================
  # TTS → overlay → BGM
  # =========================
  Stamp "=== TTS ==="
  python $TtsPy $TextPath
  Assert-File $outMp4

  Stamp "=== OVERLAY ==="
  & $OverlayPs1 $outMp4 $overlayMp4

  Stamp ("=== ADD BGM ({0}) ===" -f $Mode)
  & $BgmPs1 $outMp4

  # =========================
  # 追加：アップロード（joyuu）
  # =========================
  if ($Upload -eq "joyuu") {
    Stamp "=== UPLOAD (joyuu) ==="
    Stamp ("? python .\uploader10-joyuu.py {0}" -f $outMp4)
    python .\uploader10-joyuu.py $outMp4
  } else {
    Stamp "=== UPLOAD (none) ==="
  }

  Stamp "=== DONE ==="
  Stamp ("MP4: {0}" -f $outMp4)

}
finally {
  # =========================
  # 後片付け：処理終了時に .srt .mp3 .wav .mp4 を削除
  #  - 作業ディレクトリは TextPath と同じフォルダに限定
  #  - 最終成果物MP4は $DeleteOutputMp4 で制御（既定:残す）
  # =========================
  try {
    if ($TextPath) {
      $workDir = Split-Path -Parent $TextPath
      Stamp "=== CLEANUP ==="

      foreach ($ext in $CleanupExts) {
        Get-ChildItem -LiteralPath $workDir -File -Filter "*$ext" -ErrorAction SilentlyContinue |
          Where-Object {
            if ($ext -eq ".mp4" -and -not $DeleteOutputMp4 -and $outMp4) {
              $_.FullName -ne $outMp4
            } else {
              $true
            }
          } |
          ForEach-Object {
            Stamp ("delete: {0}" -f $_.Name)
            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
          }
      }
    }
  } catch {
    Write-Warning ("cleanup failed: {0}" -f $_.Exception.Message)
  }

  $sw.Stop()
  Write-Host ""
  Write-Host ("[TIME] start : {0}" -f $startedAt.ToString("yyyy-MM-dd HH:mm:ss"))
  Write-Host ("[TIME] total : {0:hh\:mm\:ss\.fff}" -f $sw.Elapsed)
}
