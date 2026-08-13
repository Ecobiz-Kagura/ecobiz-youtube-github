Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$start = Get-Date
Write-Host "=== 開始時刻 : $start ==="
Write-Host ""

function Run-Step([string]$Script) {
    Write-Host "[RUN] $Script"

    try {
        & $Script
    }
    catch {
        Write-Host "[ERROR] スクリプトで例外発生: $Script"
        Write-Host $_
        throw
    }
}

# =====================================================
# ★ cp スクリプト一覧（順番はそのまま）
# =====================================================
$cpList = @(
    "./cp-genpatsu.ps1",   #1
    "./cp-huudo.ps1",      #2
    "./cp-joyuu.ps1",      #3
    "./cp-kasyu.ps1",      #4
    "./cp-marx.ps1",       #5
    "./cp-sakka.ps1",      #6
    "./cp-rakugo.ps1",     #7
    "./cp-shinjuku.ps1",   #8
    "./cp-tekiya.ps1",     #9
    "./cp-yakuza.ps1",     #10
    "./cp-yoshiwara.ps1",  #11
    "./cp-cyber.ps1",      #12
    "./cp-kankyou.ps1",    #13
    "./cp-gijutsu.ps1"     #14
)

# =====================================================
# ★ ランダムに 5 個選ぶ
# =====================================================
$selected = $cpList | Get-Random -Count 5

Write-Host "=== ランダム選択された 5 個 ==="
$selected | ForEach-Object { Write-Host " - $_" }
Write-Host ""

try {
    foreach ($cp in $selected) {
        Run-Step $cp
    }
}
finally {
    # --- 例外発生でも必ず実行 ---
    $end = Get-Date
    $elapsed = $end - $start

    Write-Host ""
    Write-Host "=== 終了時刻 : $end ==="
    Write-Host ("=== 処理時間 : {0:hh\:mm\:ss\.fff} ===" -f $elapsed)
}
