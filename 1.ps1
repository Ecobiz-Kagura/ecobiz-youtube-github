# =====================================================================
# overlay3s.ps1（完全版：ショート用）
#   - 基本は overlay3.ps1 と同じ
#   - 必要なら secPerImage を短め、crf を軽め等に調整
# =====================================================================

param(
  [Parameter(Mandatory=$true)][string]$BaseMp4,
  [Parameter(Mandatory=$true)][string]$OverlaySource
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-File([string]$p){ if (-not (Test-Path -LiteralPath $p)) { throw ("Not found: {0}" -f $p) } }
function Stamp([string]$msg){
  $t = (Get-Date).ToString("HH:mm:ss")
  Write-Host ("[{0}] {1}" -f $t, $msg)
}

if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
  throw "ffmpeg not found in PATH"
}

Assert-File $BaseMp4
$BaseMp4 = (Resolve-Path $BaseMp4).Path

$baseDir  = Split-Path -Parent $BaseMp4
$baseName = [IO.Path]::GetFileNameWithoutExtension($BaseMp4)

$workDir = Join-Path $baseDir ("_ovl_tmp_{0}" -f ([Guid]::NewGuid().ToString("N")))
New-Item -ItemType Directory -Path $workDir -Force | Out-Null

$overlayMp4 = $null

try {
  if (Test-Path -LiteralPath $OverlaySource -PathType Container) {
    $imgDir = (Resolve-Path $OverlaySource).Path
    Stamp ("overlay source: image dir = {0}" -f $imgDir)

    $imgExts = @("*.png","*.jpg","*.jpeg","*.webp","*.bmp")
    $images = foreach ($ext in $imgExts) {
      Get-ChildItem -LiteralPath $imgDir -File -Filter $ext -ErrorAction SilentlyContinue
    }
    if (-not $images -or $images.Count -eq 0) {
      throw ("no images found in: {0}" -f $imgDir)
    }

    # ★完全シャッフル
    $images = $images | Get-Random -Count $images.Count

    # ショートはテンポ早め
    $secPerImage = 2
    $fps = 30

    $listFile = Join-Path $workDir "images_rand.txt"
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($img in $images) {
      $p = $img.FullName.Replace("'", "''")
      $lines.Add(("file '{0}'" -f $p))
      $lines.Add(("duration {0}" -f $secPerImage))
    }
    $last = $images[$images.Count-1].FullName.Replace("'", "''")
    $lines.Add(("file '{0}'" -f $last))
    $lines | Set-Content -LiteralPath $listFile -Encoding UTF8

    $overlayMp4 = Join-Path $workDir "slideshow_rand.mp4"

    Stamp "build slideshow (random order)"
    & ffmpeg -y `
      -hide_banner -loglevel error `
      -f concat -safe 0 -i $listFile `
      -r $fps `
      -vf "format=yuv420p" `
      -c:v libx264 -preset veryfast -crf 20 `
      $overlayMp4

    Assert-File $overlayMp4
  }
  else {
    Assert-File $OverlaySource
    $overlayMp4 = (Resolve-Path $OverlaySource).Path
    Stamp ("overlay source: mp4 = {0}" -f $overlayMp4)
  }

  $tmpOut = Join-Path $workDir ("{0}_overlay_tmp.mp4" -f $baseName)

  Stamp "ffmpeg overlay"
  & ffmpeg -y `
    -hide_banner -loglevel error `
    -i $BaseMp4 `
    -i $overlayMp4 `
    -filter_complex `
    "[1:v]scale=iw:ih:force_original_aspect_ratio=decrease,scale=trunc(iw/2)*2:trunc(ih/2)*2[ov];[0:v][ov]overlay=0:0:shortest=1" `
    -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p `
    -c:a copy `
    $tmpOut

  Assert-File $tmpOut
  Stamp "replace base mp4"
  Move-Item -LiteralPath $tmpOut -Destination $BaseMp4 -Force

  Stamp "overlay done"

}
finally {
  try {
    if (Test-Path -LiteralPath $workDir) {
      Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
    }
  } catch {}
}
