param(
  [Parameter(Position=0, Mandatory=$true)]
  [string]$InputPs1,

  [Parameter(Position=1, Mandatory=$false)]
  [ValidateSet("none","epilogue","ghost","silent","twilight")]
  [string]$BgmTheme = "none",

  # 名前付きで指定（例: -UploadMode kankyou）
  [Parameter(Mandatory=$false)]
  [string]$UploadMode = "kankyou",

  # アップロードをスキップ
  [Parameter(Mandatory=$false)]
  [switch]$SkipUpload,

  # 音量倍率（1.0 = そのまま）※overlay の声（wav）側
  [Parameter(Mandatory=$false)]
  [double]$VoiceGain = 1.0,

  # BGM音量（0.0?2.0）
  [Parameter(Mandatory=$false)]
  [double]$BgmVolume = 0.14,

  # 元動画音量（0.0?2.0）※BGMスクリプト側が対応している場合のみ有効
  [Parameter(Mandatory=$false)]
  [double]$MainVolume = 1.00
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

# 音量は安全範囲へ（実効値はこの後の値）
$VoiceGain  = Clamp $VoiceGain  0.0 4.0
$BgmVolume  = Clamp $BgmVolume  0.0 2.0
$MainVolume = Clamp $MainVolume 0.0 2.0

# ------------------------------------------------------------
# ★変更：すべての y/N を 10秒無入力で自動Y に統一
#  - 戻り値: "y" or "n"
# ------------------------------------------------------------
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

    # 入力が y/n なら即確定
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

  # Enter 押下時：空や不正は auto y
  if([string]::IsNullOrWhiteSpace($buf)){
    Write-Host "(auto) y"
    return "y"
  }
  $t = $buf.Trim().ToLower()
  if($t -eq "y" -or $t -eq "n"){ return $t }

  Write-Host "(auto) y"
  return "y"
}

# ------------------------------------------------------------
# ★起動直後に「カレントの mp4 を削除」(y/N) / 10秒無入力で自動Y
# ------------------------------------------------------------
function Confirm-AndDeleteMp4InCwd {
  param([int]$timeoutSec = 10)

  $cwd0 = (Get-Location).Path
  $mp4s = Get-ChildItem -LiteralPath $cwd0 -File -Filter "*.mp4" -ErrorAction SilentlyContinue

  if(-not $mp4s -or $mp4s.Count -eq 0){
    Write-Host "カレントに mp4 はありません: $cwd0"
    return
  }

  Write-Host ""
  Write-Host "====================================================="
  Write-Host "  事前処理：カレントの mp4 削除"
  Write-Host "====================================================="
  Write-Host ("対象: {0}" -f $cwd0)
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
    Write-Host "mp4 削除はスキップしました。"
    return
  }

  foreach($f in $mp4s){
    try{
      Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
    } catch {
      throw "[ERROR] mp4 削除に失敗しました: $($f.FullName)`n$($_ | Out-String)"
    }
  }

  Write-Host "mp4 を削除しました。"
}

# ★ここで実行（要望どおり「最初に」）
Confirm-AndDeleteMp4InCwd -timeoutSec 10

# ------------------------------------------------------------
# 便利関数群
# ------------------------------------------------------------
function Pick-LatestInDir([string]$dir, [string]$pattern){
  if(-not (Test-Path -LiteralPath $dir)){ return $null }
  Get-ChildItem -LiteralPath $dir -File -Filter $pattern -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
}

function Esc-Subs([string]$p){
  ($p -replace "\\","/" -replace ":","\:" -replace "'","\'")
}

function Resolve-BgmScript([string]$theme){
  if($theme -eq "none"){ return "" }
  $p1 = Join-Path $PSScriptRoot ("add-BGM-{0}.ps1" -f $theme)
  $p2 = Join-Path $PSScriptRoot ("add_BGM_{0}.ps1" -f $theme)
  if(Test-Path -LiteralPath $p1){ return $p1 }
  if(Test-Path -LiteralPath $p2){ return $p2 }
  Fail "BGMスクリプトが見つかりません: $p1 または $p2"
}

function Get-LatestMp4AfterExcluding([string]$dir, [datetime]$after, [string[]]$excludePaths){
  $exclude = @{}
  foreach($e in $excludePaths){
    if($e -and (Test-Path -LiteralPath $e)){
      $exclude[(Resolve-Path -LiteralPath $e).Path.ToLower()] = $true
    }
  }

  Get-ChildItem -LiteralPath $dir -File -Filter "*.mp4" -ErrorAction SilentlyContinue |
    Where-Object {
      $_.LastWriteTime -ge $after -and -not $exclude[$_.FullName.ToLower()]
    } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
}

function Get-LatestMp4Excluding([string]$dir, [string[]]$excludePaths){
  $exclude = @{}
  foreach($e in $excludePaths){
    if($e -and (Test-Path -LiteralPath $e)){
      $exclude[(Resolve-Path -LiteralPath $e).Path.ToLower()] = $true
    }
  }

  Get-ChildItem -LiteralPath $dir -File -Filter "*.mp4" -ErrorAction SilentlyContinue |
    Where-Object { -not $exclude[$_.FullName.ToLower()] } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
}

function Get-TargetMp4([string]$dir, [datetime]$since, [string[]]$excludePaths){
  $m = Get-LatestMp4AfterExcluding $dir $since $excludePaths
  if($m){ return $m.FullName }

  $m = Get-LatestMp4Excluding $dir $excludePaths
  if($m){ return $m.FullName }

  return $null
}

function Invoke-BgmScriptCompat([string]$bgmScriptPath, [string]$inputMp4, [double]$bgmVol, [double]$mainVol){
  try{
    & $bgmScriptPath -InputMp4 $inputMp4 -BgmVolume $bgmVol -MainVolume $mainVol
  } catch {
    $msg = ($_ | Out-String)
    if($msg -match "A parameter cannot be found" -or $msg -match "パラメーター名.*が見つかりません"){
      Write-Host "BGMスクリプトが音量引数に未対応のため、旧呼び出しにフォールバックします。"
      & $bgmScriptPath $inputMp4
    } else {
      throw
    }
  }
}

# ------------------------------------------------------------
# ★SRTを短く分割して「一回に表示する字幕の量」を減らす（方法1）
# ------------------------------------------------------------
$SrtMaxChars = 18
$SrtMinChunkSec = 0.20

function Parse-SrtTime([string]$t){
  if($t -notmatch '^(\d\d):(\d\d):(\d\d),(\d\d\d)$'){ return $null }
  $hh = [int]$Matches[1]; $mm = [int]$Matches[2]; $ss = [int]$Matches[3]; $ms = [int]$Matches[4]
  return New-TimeSpan -Hours $hh -Minutes $mm -Seconds $ss -Milliseconds $ms
}

function Format-SrtTime([TimeSpan]$ts){
  $totalHours = [int][Math]::Floor($ts.TotalHours)
  return ("{0:00}:{1:00}:{2:00},{3:000}" -f $totalHours, $ts.Minutes, $ts.Seconds, $ts.Milliseconds)
}

function Split-TextByChars([string]$text, [int]$maxChars){
  $t = ($text -replace '\s+',' ').Trim()
  if([string]::IsNullOrWhiteSpace($t)){ return @() }

  $chunks = New-Object System.Collections.Generic.List[string]
  $p = 0
  while($p -lt $t.Length){
    $len = [Math]::Min($maxChars, $t.Length - $p)
    $chunks.Add($t.Substring($p, $len).Trim())
    $p += $len
  }
  return $chunks.ToArray()
}

function Write-Utf8NoBomLines([string]$path, [string[]]$lines){
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllLines($path, $lines, $enc)
}

function Make-SmallSrt([string]$inputSrtPath, [string]$outputSrtPath, [int]$maxChars, [double]$minChunkSec){
  $raw = [System.IO.File]::ReadAllText($inputSrtPath, [System.Text.Encoding]::UTF8)
  $blocks = $raw -split "(\r?\n){2,}"

  $out = New-Object System.Collections.Generic.List[string]
  $newIndex = 1

  foreach($b in $blocks){
    $bb = $b.Trim()
    if($bb -eq ""){ continue }

    $lines = $bb -split "\r?\n"
    if($lines.Count -lt 3){ continue }

    $timeLine = $lines[1].Trim()
    if($timeLine -notmatch '^\s*(\d\d:\d\d:\d\d,\d\d\d)\s*-->\s*(\d\d:\d\d:\d\d,\d\d\d)'){
      continue
    }

    $t0 = Parse-SrtTime $Matches[1]
    $t1 = Parse-SrtTime $Matches[2]
    if(-not $t0 -or -not $t1){ continue }

    $text = ($lines[2..($lines.Count-1)] -join " ").Trim()
    if([string]::IsNullOrWhiteSpace($text)){ continue }

    $chunks = Split-TextByChars $text $maxChars
    if($chunks.Count -le 1){
      $out.Add([string]$newIndex); $newIndex++
      $out.Add($timeLine)
      $out.Add($text)
      $out.Add("")
      continue
    }

    $dur = ($t1 - $t0).TotalSeconds
    $per = $dur / [double]$chunks.Count

    if($per -lt $minChunkSec){
      $out.Add([string]$newIndex); $newIndex++
      $out.Add($timeLine)
      $out.Add($text)
      $out.Add("")
      continue
    }

    for($i=0; $i -lt $chunks.Count; $i++){
      $s = $t0 + [TimeSpan]::FromSeconds($per * $i)
      $e = $t0 + [TimeSpan]::FromSeconds($per * ($i + 1))

      $out.Add([string]$newIndex); $newIndex++
      $out.Add(("{0} --> {1}" -f (Format-SrtTime $s), (Format-SrtTime $e)))
      $out.Add($chunks[$i])
      $out.Add("")
    }
  }

  Write-Utf8NoBomLines $outputSrtPath ($out.ToArray())
}

# ------------------------------------------------------------
# 0) 事前情報
# ------------------------------------------------------------
$scriptStart = Get-Date

$ps1 = (Resolve-Path -LiteralPath $InputPs1 -ErrorAction Stop).Path
$cwd = (Get-Location).Path

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$outOverlay = Join-Path $cwd ("overlay_{0}.mp4" -f $ts)

$bgmScript = Resolve-BgmScript $BgmTheme
$uploader  = Join-Path $cwd "uploader11.py"

# 予定表示用（存在しない可能性があるので null 許容）
$srtPrev = Pick-LatestInDir $cwd "*.srt"
$finalPrev = $null
if($srtPrev){
  $srtBasePrev = [IO.Path]::GetFileNameWithoutExtension($srtPrev.FullName)
  $finalPrev = Join-Path $cwd ("{0}.mp4" -f $srtBasePrev)
}

# 表示用：実行BGMスクリプト名
$bgmScriptLabel = "（なし）"
if($BgmTheme -ne "none"){
  $bgmScriptLabel = [IO.Path]::GetFileName($bgmScript) + "  (" + $bgmScript + ")"
}

# ------------------------------------------------------------
# 1) 予定表示（★音量・BGMスクリプト名を表示）
#    ★変更：y/N は 10秒無入力で自動Y
# ------------------------------------------------------------
Write-Host ""
Write-Host "====================================================="
Write-Host "  実行予定"
Write-Host "====================================================="
Write-Host "生成 ps1:           $ps1"
Write-Host "overlay 出力:        $outOverlay"
if($finalPrev){
  Write-Host "最終出力(予定):      $finalPrev"
}else{
  Write-Host "最終出力(予定):      （srt未検出のため後で確定）"
}

Write-Host "-------------------------------------"
Write-Host "音量（実効値 / Clamp後）"
Write-Host ("  声(overlay wav)  : {0}" -f $VoiceGain)
Write-Host ("  BGM              : {0}" -f $BgmVolume)
Write-Host ("  元動画(main)     : {0}" -f $MainVolume)

Write-Host "-------------------------------------"
Write-Host ("BGMテーマ:           {0}" -f $BgmTheme)
Write-Host ("実行BGMスクリプト:    {0}" -f $bgmScriptLabel)

Write-Host "-------------------------------------"
Write-Host ("字幕短縮:            maxChars={0}  minChunkSec={1}" -f $SrtMaxChars, $SrtMinChunkSec)
Write-Host "処理対象mp4:          カレントで今回作成された最新mp4（無ければ最新mp4）"
if(-not $SkipUpload){
  Write-Host "uploader11.py:        python uploader11.py --mode $UploadMode"
}else{
  Write-Host "uploader:             スキップ"
}
Write-Host ""

$ans = Read-YesNoTimeoutDefaultY "実行しますか？ (y/N) [10秒で自動Y]: " 10
if($ans -ne "y"){ return }

# ------------------------------------------------------------
# 2) 生成 ps1 実行
# ------------------------------------------------------------
& $ps1
if($LASTEXITCODE -ne 0){
  Fail "生成 ps1 が異常終了しました: $ps1"
}

$wav = Pick-LatestInDir $cwd "*.wav"
$srt = Pick-LatestInDir $cwd "*.srt"
if(-not $wav){ Fail "wav が見つかりません（生成 ps1 の出力を確認）" }
if(-not $srt){ Fail "srt が見つかりません（生成 ps1 の出力を確認）" }

$srtBase  = [IO.Path]::GetFileNameWithoutExtension($srt.FullName)
$finalOut = Join-Path $cwd ("{0}.mp4" -f $srtBase)

# ★短縮SRTを作る（字幕量を減らす）
$tmpSmallSrt = Join-Path $cwd ("_srt_small_{0}.srt" -f $ts)
$useSrtPath = $srt.FullName
try{
  Make-SmallSrt -inputSrtPath $srt.FullName -outputSrtPath $tmpSmallSrt -maxChars $SrtMaxChars -minChunkSec $SrtMinChunkSec
  if(Test-Path -LiteralPath $tmpSmallSrt){
    $useSrtPath = $tmpSmallSrt
    Write-Host "短縮SRT: $tmpSmallSrt"
  } else {
    Write-Host "短縮SRTが生成されなかったため、元SRTを使用します。"
  }
} catch {
  Write-Host "短縮SRTの生成に失敗したため、元SRTを使用します。"
}

# ------------------------------------------------------------
# 3) overlay 作成（背景 = “今回作成された最新mp4”）
# ------------------------------------------------------------
$excludeForBg = @($outOverlay, $finalOut)

$bg = Get-TargetMp4 $cwd $scriptStart $excludeForBg
if(-not $bg){
  Fail "処理対象の mp4 が見つかりません（カレントに mp4 がありません）"
}
Write-Host "背景（処理対象）: $bg"

$se = Esc-Subs $useSrtPath
$style = "FontSize=12,Alignment=2,MarginV=60,Outline=1,Shadow=0"

$fc = @(
  "[0:v]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,setsar=1[v0]",
  "[v0]subtitles='$se':original_size=1080x1920:force_style='$style'[vout]"
) -join ";"

ffmpeg -y -hide_banner `
  -i $bg `
  -i $wav.FullName `
  -filter_complex $fc `
  -map "[vout]" -map "1:a:0" `
  -af ("volume={0},alimiter=limit=0.98" -f $VoiceGain) `
  -shortest `
  -c:v libx264 -preset veryfast -pix_fmt yuv420p -crf 18 `
  -c:a aac -b:a 192k `
  $outOverlay

if($LASTEXITCODE -ne 0){
  Fail "ffmpeg(overlay) が失敗しました。背景mp4や音声パスを確認してください。背景: $bg"
}
if(-not (Test-Path -LiteralPath $outOverlay)){
  Fail "overlay 出力が生成されませんでした: $outOverlay"
}

$baseForFinal = $outOverlay

# ------------------------------------------------------------
# 4) BGM
# ------------------------------------------------------------
if($BgmTheme -ne "none"){
  $exclude = @($bg, $outOverlay, $finalOut, $baseForFinal)
  $t0 = Get-Date

  Invoke-BgmScriptCompat $bgmScript $baseForFinal $BgmVolume $MainVolume

  if($LASTEXITCODE -ne 0){
    Fail "BGMスクリプトが異常終了しました: $bgmScript"
  }

  $newMp4 = Get-LatestMp4AfterExcluding $cwd $t0 $exclude
  if(-not $newMp4){
    $newMp4 = Get-LatestMp4Excluding $cwd $exclude
  }
  if(-not $newMp4){
    Fail "BGM後の mp4 が見つかりません（BGMスクリプトの出力を確認）"
  }

  $baseForFinal = $newMp4.FullName
  Write-Host "BGM後 mp4: $baseForFinal"
}

# ------------------------------------------------------------
# 5) srt と同名で保存
# ------------------------------------------------------------
Copy-Item -LiteralPath $baseForFinal -Destination $finalOut -Force
Write-Host "Saved final: $finalOut"

# ------------------------------------------------------------
# 6) uploader（mode の検証なし）
# ------------------------------------------------------------
if(-not $SkipUpload){
  if(-not (Test-Path -LiteralPath $uploader)){
    Fail "uploader11.py が見つかりません: $uploader"
  }

  Write-Host ""
  Write-Host "Uploader 実行: python uploader11.py --mode $UploadMode"
  & python $uploader --mode $UploadMode
  if($LASTEXITCODE -ne 0){
    Fail "uploader11.py が異常終了しました。"
  }
}

# ------------------------------------------------------------
# 後始末（短縮SRTが一時ファイルなら消す）
# ------------------------------------------------------------
try{
  if($useSrtPath -and ($useSrtPath -like "*_srt_small_*") -and (Test-Path -LiteralPath $useSrtPath)){
    Remove-Item -LiteralPath $useSrtPath -Force -ErrorAction SilentlyContinue
  }
} catch {}

Write-Host "完了しました。"
