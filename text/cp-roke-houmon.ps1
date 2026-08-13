param(
  [Parameter(Mandatory=$true)]
  [string]$Prefix  # 例: 20260213-025220
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$DestDir = "D:\【エコビズ】\【ロケ練-訪問】"

function Read-YesNoTimeout {
    param(
        [int]$TimeoutSec = 5
    )

    Write-Host "実行しますか？ (y/N) ※${TimeoutSec}秒で自動Y"
    $stopWatch = [System.Diagnostics.Stopwatch]::StartNew()

    while ($stopWatch.Elapsed.TotalSeconds -lt $TimeoutSec) {
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            if ($key.Key -eq "Y") { return $true }
            if ($key.Key -eq "N") { return $false }
        }
        Start-Sleep -Milliseconds 100
    }

    Write-Host "→ 自動Y"
    return $true
}

function Get-LatestByPrefix([string]$ext){
    Get-ChildItem -LiteralPath (Get-Location) -File -Filter "$Prefix*.$ext" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
}

# 対象収集
$targets = @()
foreach ($ext in "css","wav","mp4","srt") {
    $f = Get-LatestByPrefix $ext
    if ($f) { $targets += $f }
}

if ($targets.Count -eq 0) {
    Write-Host "対象ファイルが見つかりません。"
    exit
}

Write-Host "=== コピー予定 ==="
$targets | ForEach-Object { Write-Host $_.Name }
Write-Host "→ $DestDir"
Write-Host "===================="

if (-not (Read-YesNoTimeout 5)) {
    Write-Host "キャンセルしました。"
    exit
}

if (-not (Test-Path -LiteralPath $DestDir)) {
    New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
}

foreach ($f in $targets) {
    $dst = Join-Path -Path $DestDir -ChildPath $f.Name
    Copy-Item -LiteralPath $f.FullName -Destination $dst -Force
    Write-Host "[OK] $($f.Name)"
}

Write-Host "完了しました。"
