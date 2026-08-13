# run-eco-epilogue.ps1
# エコ系エピローグ動画を自動生成 → オーバーレイ → BGM → アップロード → txt 移動まで一括実行

param (
    [Parameter(Mandatory = $true)]
    [string]$textFilePath,       # 例: .\20250511220157-159-廃木材バイオエタノール...解説.txt

    [Parameter(Mandatory = $true)]
    [string]$overlayVideoPath    # 例: .\10-bio-2.mp4 （メインの eco 背景）
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ======================================
# ★ 実行プログラム / スクリプト設定 ★
# ======================================

# 実行に使う python
$PYTHON_EXE          = 'python'   # 必要ならフルパスに変更: 'C:\Python311\python.exe' など

# Python スクリプト
$SCRIPT_TTS          = '.\9.py'                # テキスト→TTS動画
$SCRIPT_UPLOADER     = '.\uploader10-eco.py'   # YouTube アップロード

# PowerShell スクリプト
$SCRIPT_OVERLAY_MAIN = '.\overlay3.ps1'        # メイン eco 背景オーバーレイ
$SCRIPT_OVERLAY_LEFT = '.\overlay3-topleft.ps1'# 左上オーバーレイ
$SCRIPT_OVERLAY_RIGHT= '.\overlay3-topright.ps1'# 右上オーバーレイ
$SCRIPT_ADD_BGM      = '.\add-bgm-epilogue.ps1'# エピローグBGM追加

# 外部プログラム
$FFMPEG              = 'D:\ffmpeg.exe'         # ffmpeg 実行ファイル

# ======================================
# ★ ディレクトリ設定 ★
# ======================================

# eco 系素材
$DIR_ECO_ORG   = 'D:\images_for_slide_show\MP4s-epilogue\eco-org'    # LEFT 用 元素材
$DIR_LEFT_ECO  = 'D:\images_for_slide_show\MP4s-epilogue\left\eco'   # LEFT 合成出力
$DIR_RIGHT     = 'D:\images_for_slide_show\MP4s-epilogue\right'      # RIGHT 素材

# OneDrive 側
$DIR_ONEDRIVE_TODAY = 'C:\Users\user\OneDrive\＊【エコビズ】\today'
$DIR_ONEDRIVE_DONE  = Join-Path $DIR_ONEDRIVE_TODAY 'done'

# D: 側「話の特集」
$DIR_HANASHI      = 'D:\【エコビズ】\話の特集'
$DIR_HANASHI_DONE = Join-Path $DIR_HANASHI 'done'

# ======================================
# 0) 元ファイル情報（後で done 移動に使用）
# ======================================

$origLeaf = Split-Path -Leaf $textFilePath
$origBase = [IO.Path]::GetFileNameWithoutExtension($origLeaf)

# ※必要ならバックアップ処理を有効化
# $srcDir    = Split-Path -Parent $textFilePath
# $backupDir = Join-Path $srcDir "_backup"
# if (-not (Test-Path -LiteralPath $backupDir)) {
#     New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
# }
# $ts = Get-Date -Format "yyyyMMdd-HHmmss"
# $backupName = "{0}__backup__{1}{2}" -f $origBase, $ts, [IO.Path]::GetExtension($textFilePath)
# Copy-Item -LiteralPath $textFilePath -Destination (Join-Path $backupDir $backupName) -Force

# ======================================
# 1) ベース名・mp4 パス算出
# ======================================

$baseName = [IO.Path]::GetFileNameWithoutExtension($textFilePath)
$safeBase = $baseName.TrimEnd('.', '。', ' ')
$txtDir   = Split-Path -Parent $textFilePath
$mp4File  = Join-Path $txtDir "$safeBase.mp4"

Write-Host "=== 1) TTS 動画生成 ($SCRIPT_TTS) ==="
Write-Host "? $PYTHON_EXE $SCRIPT_TTS `"$textFilePath`""
& $PYTHON_EXE $SCRIPT_TTS $textFilePath

if (-not (Test-Path -LiteralPath $mp4File)) {
    throw "TTS 実行後のベース動画が見つかりません: $mp4File"
}

# ======================================
# 2) メイン eco 背景オーバーレイ (overlay3.ps1)
# ======================================

Write-Host "=== 2) メイン eco 背景オーバーレイ ($SCRIPT_OVERLAY_MAIN) ==="
Write-Host "? $SCRIPT_OVERLAY_MAIN `"$mp4File`" `"$overlayVideoPath`""
& $SCRIPT_OVERLAY_MAIN $mp4File $overlayVideoPath

# ======================================
# 3) LEFT 用：eco-org から 8 本ランダム結合
# ======================================

Write-Host "=== 3) LEFT eco 結合動画生成 (ffmpeg) ==="

if (-not (Test-Path -LiteralPath $DIR_ECO_ORG)) {
    throw "Source not found: $DIR_ECO_ORG"
}

if (-not (Test-Path -LiteralPath $DIR_LEFT_ECO)) {
    New-Item -ItemType Directory -Path $DIR_LEFT_ECO -Force | Out-Null
}

# 古い LEFT eco mp4 を削除（フォルダ限定）
Get-ChildItem -LiteralPath $DIR_LEFT_ECO -Filter *.mp4 -File -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue

$mergeOutFile = Join-Path $DIR_LEFT_ECO ("eco-merge-{0}.mp4" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

$mp4s = Get-ChildItem -LiteralPath $DIR_ECO_ORG -File -Filter *.mp4
if ($mp4s.Count -lt 5) {
    throw "eco-org 内の MP4 が 5 本未満です: $($mp4s.Count)"
}

$pick = $mp4s | Get-Random -Count 8

Write-Host "=== 選択された eco-org 動画 ==="
$pick | ForEach-Object { Write-Host "  $($_.Name)" }

# concat list（UTF-8 BOM なし）
$tmpList = [System.IO.Path]::GetTempFileName()

$lines = $pick | ForEach-Object {
    $p = $_.FullName.Replace("'", "''")
    "file '$p'"
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllLines($tmpList, $lines, $utf8NoBom)

# ffmpeg 結合
$ffArgs = @(
    '-y',
    '-f','concat',
    '-safe','0',
    '-i', $tmpList,
    '-map','0:v:0',
    '-map','0:a?',
    '-c:v','libx264',
    '-preset','veryfast',
    '-crf','20',
    '-pix_fmt','yuv420p',
    '-movflags','+faststart',
    $mergeOutFile
)

Write-Host "=== ffmpeg (LEFT eco merge) 実行: $FFMPEG ==="
& $FFMPEG @ffArgs

Remove-Item -LiteralPath $tmpList -Force

Write-Host "LEFT eco 結合出力: $mergeOutFile"

# ======================================
# 4) LEFT トップオーバーレイ (overlay3-topleft.ps1)
# ======================================

Write-Host "=== 4) LEFT トップオーバーレイ ($SCRIPT_OVERLAY_LEFT) ==="

if (-not (Test-Path -LiteralPath $mp4File)) {
    throw "元動画が見つかりません (LEFT overlay 前): $mp4File"
}

$leftOverlay = Get-ChildItem -LiteralPath $DIR_LEFT_ECO -File -Filter *.mp4 | Get-Random
if (-not $leftOverlay) {
    throw "$DIR_LEFT_ECO に *.mp4 がありません。"
}

Write-Host "? $SCRIPT_OVERLAY_LEFT `"$mp4File`" `"$($leftOverlay.FullName)`""
& $SCRIPT_OVERLAY_LEFT $mp4File $leftOverlay.FullName

# ======================================
# 5) RIGHT トップオーバーレイ (overlay3-topright.ps1)
# ======================================

Write-Host "=== 5) RIGHT トップオーバーレイ ($SCRIPT_OVERLAY_RIGHT) ==="

if (-not (Test-Path -LiteralPath $mp4File)) {
    throw "元動画が見つかりません (RIGHT overlay 前): $mp4File"
}

if (-not (Test-Path -LiteralPath $DIR_RIGHT)) {
    throw "RIGHT 素材ディレクトリが見つかりません: $DIR_RIGHT"
}

$rightOverlay = Get-ChildItem -LiteralPath $DIR_RIGHT -File -Filter *.mp4 | Get-Random
if (-not $rightOverlay) {
    throw "$DIR_RIGHT に *.mp4 がありません。"
}

Write-Host "? $SCRIPT_OVERLAY_RIGHT `"$mp4File`" `"$($rightOverlay.FullName)`""
& $SCRIPT_OVERLAY_RIGHT $mp4File $rightOverlay.FullName

# ======================================
# 6) エピローグ用 BGM 追加 (add-bgm-epilogue.ps1)
# ======================================

Write-Host "=== 6) エピローグ用 BGM 追加 ($SCRIPT_ADD_BGM) ==="
Write-Host "? $SCRIPT_ADD_BGM `"$mp4File`""
& $SCRIPT_ADD_BGM $mp4File

# ======================================
# 7) アップロード (uploader10-eco.py)
# ======================================

Write-Host "=== 7) アップロード ($SCRIPT_UPLOADER) ==="
Write-Host "? $PYTHON_EXE $SCRIPT_UPLOADER `"$mp4File`""
& $PYTHON_EXE $SCRIPT_UPLOADER $mp4File

# ======================================
# 8) OneDrive\today の txt を done へ移動
# ======================================

Write-Host "=== 8) OneDrive\\today の txt を done へ移動 ==="

if (-not (Test-Path -LiteralPath $DIR_ONEDRIVE_TODAY)) {
    Write-Warning "OneDrive today ディレクトリが見つかりません: $DIR_ONEDRIVE_TODAY"
} else {
    if (-not (Test-Path -LiteralPath $DIR_ONEDRIVE_DONE)) {
        New-Item -Path $DIR_ONEDRIVE_DONE -ItemType Directory -Force | Out-Null
    }

    $origTxt = Join-Path $DIR_ONEDRIVE_TODAY ($origBase + ".txt")
    if (Test-Path -LiteralPath $origTxt) {
        $dest = Join-Path $DIR_ONEDRIVE_DONE ([IO.Path]::GetFileName($origTxt))
        Move-Item -LiteralPath $origTxt -Destination $dest -Force
        Write-Host "? Moved to done: $dest"
    } else {
        Write-Warning "? $($origBase).txt not found in OneDrive 'today'."
    }
}

# ======================================
# 9) D:\【エコビズ】\話の特集 側の done へ移動
# ======================================

Write-Host "=== 9) D:\【エコビズ】\話の特集 側の done 処理 ==="

if (-not (Test-Path -LiteralPath $DIR_HANASHI)) {
    Write-Warning "話の特集 ディレクトリが見つかりません: $DIR_HANASHI"
} else {
    if (-not (Test-Path -LiteralPath $DIR_HANASHI_DONE)) {
        New-Item -Path $DIR_HANASHI_DONE -ItemType Directory -Force | Out-Null
    }

    # 話の特集 フォルダ内で最新の mp4 を基準に txt を探す
    $latestVideo = Get-ChildItem -Path $DIR_HANASHI -Filter '*.mp4' -File -ErrorAction SilentlyContinue |
                   Sort-Object LastWriteTime -Descending |
                   Select-Object -First 1

    if ($latestVideo) {
        $bn2  = [System.IO.Path]::GetFileNameWithoutExtension($latestVideo.Name)
        $txt2 = Join-Path $DIR_HANASHI "$bn2.txt"
        if (Test-Path -LiteralPath $txt2) {
            $destTxt2 = Join-Path $DIR_HANASHI_DONE "$bn2.txt"
            Move-Item -LiteralPath $txt2 -Destination $destTxt2 -Force
            Write-Host "対応するテキストファイルを移動しました: $destTxt2"
        } else {
            Write-Host "対応するテキストファイルが見つかりません: $txt2"
        }
    } else {
        Write-Host "話の特集 ディレクトリに mp4 が見つかりませんでした。"
    }
}

# ======================================
# 10) 一時 mp4 の削除（必要なら個別に）
# ======================================

# ★ 全 *.mp4 削除は危険なのでコメントアウトしています。
# Remove-Item *.mp4 -Force

Write-Host "=== run-eco-epilogue.ps1 完了 ==="