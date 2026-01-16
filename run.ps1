# =================================================================
# run.ps1（完全版：異常終了時も処理時間表示）
# =================================================================

param(
    # ---- charamin 側 ----
    [string]$Mode = "epilogue",
    [switch]$MakeWide,
    [int]$WideFontSize = 20,

    # ---- overlay 側 ----
    [string]$OverlayTheme,
    [string]$OverlayFrom
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# -------------------------
# 共通ユーティリティ
# -------------------------
function NowString {
    (Get-Date).ToString("yyyy/MM/dd HH:mm:ss")
}

function Format-Elapsed {
    param([TimeSpan]$ts)
    ('{0:00}:{1:00}:{2:00}' -f [int]$ts.TotalHours, $ts.Minutes, $ts.Seconds)
}

# -------------------------
# 子 pwsh 実行（30秒ごとに必ず表示）
# -------------------------
function Run-PwshWithHeartbeat {
    param(
        [Parameter(Mandatory=$true)][string]$ScriptPath,
        [Parameter(Mandatory=$true)][string[]]$ScriptArgs
    )

    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        throw "スクリプトが見つかりません: $ScriptPath"
    }

    $argLine = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $ScriptPath
    ) + $ScriptArgs

    Write-Host "-------------------------"
    Write-Host "[CHILD-CMD]"
    Write-Host ("pwsh.exe {0}" -f ($argLine -join ' '))
    Write-Host "-------------------------"

    $process = Start-Process `
        -FilePath "pwsh.exe" `
        -ArgumentList $argLine `
        -NoNewWindow `
        -PassThru

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $lastPrinted = 0

    while (-not $process.HasExited) {
        Start-Sleep -Seconds 1
        $elapsedSec = [int]$sw.Elapsed.TotalSeconds
        if (($elapsedSec - $lastPrinted) -ge 30) {
            $lastPrinted = $elapsedSec
            Write-Host (
                "[TICK] 時刻={0} 経過秒={1} 経過時間={2} PID={3} スクリプト={4}" -f
                (NowString),
                $elapsedSec,
                (Format-Elapsed $sw.Elapsed),
                $process.Id,
                $ScriptPath
            )
        }
    }

    $sw.Stop()

    Write-Host (
        "[CHILD-END] exitcode={0} 経過秒={1} 経過時間={2} スクリプト={3}" -f
        $process.ExitCode,
        $sw.Elapsed.TotalSeconds.ToString("0.0"),
        (Format-Elapsed $sw.Elapsed),
        $ScriptPath
    )

    if ($process.ExitCode -ne 0) {
        throw "子プロセス異常終了: $ScriptPath (exitcode=$($process.ExitCode))"
    }
}

# -------------------------
# STEP ラッパー（処理時間表示）
# -------------------------
function Run-Step {
    param(
        [Parameter(Mandatory=$true)][string]$Title,
        [Parameter(Mandatory=$true)][scriptblock]$Body
    )

    Write-Host "========================="
    Write-Host "[START] $Title"
    Write-Host "開始時刻 : $(NowString)"
    Write-Host "========================="

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    & $Body
    $sw.Stop()

    Write-Host "-------------------------"
    Write-Host "[END] $Title"
    Write-Host "終了時刻 : $(NowString)"
    Write-Host "処理時間 : $($sw.Elapsed.TotalSeconds.ToString('0.0')) 秒 ($(Format-Elapsed $sw.Elapsed))"
    Write-Host ""
}

# ================================================================
# TOTAL 計測開始（★異常終了でも finally で表示）
# ================================================================
$TOTAL_START = NowString
$TOTAL_SW = [System.Diagnostics.Stopwatch]::StartNew()

try {

    # ============================================================
    # STEP1: charamin-overlay3
    # ============================================================
    Run-Step "charamin-overlay3" {

        $args = @(
            ".\11-yakuza-1970.ps1",
            $Mode
        )

        if ($MakeWide) {
            $args += @(
                "-MakeWide",
                "-WideFontSize",
                "$WideFontSize"
            )
        }

        Run-PwshWithHeartbeat `
            -ScriptPath ".\charamin-overlay3.ps1" `
            -ScriptArgs $args
    }

    # ============================================================
    # STEP2: overlay11
    # ============================================================
    Run-Step "overlay11" {

        $args = @()

        if ($OverlayTheme) {
            $args += @("-OverlayTheme", $OverlayTheme)
        }

        if ($OverlayFrom) {
            $args += @("-OverlayFrom", $OverlayFrom)
        }

        Run-PwshWithHeartbeat `
            -ScriptPath ".\overlay11.ps1" `
            -ScriptArgs $args
    }

    # ============================================================
    # STEP3: add_BGM（Mode に応じてスクリプト切替・余計な引数なし）
    # ============================================================
    Run-Step "add_BGM (mode switch)" {

        Write-Host "Mode : $Mode"

        $bgmScript = $null

        if ($Mode -eq "epilogue") {
            $bgmScript = ".\add_BGM_epilogue.ps1"
        }
        elseif ($Mode -eq "ghost") {
            $bgmScript = ".\add_BGM_ghost.ps1"
        }

        if (-not $bgmScript) {
            Write-Host "add_BGM は実行しません（対応する Mode ではありません）"
            return
        }

        Write-Host "add_BGM スクリプト : $bgmScript"

        $inputMp4 = Get-ChildItem -Path . -Filter "*.mp4" |
                    Sort-Object LastWriteTime -Descending |
                    Select-Object -First 1 |
                    Select-Object -ExpandProperty FullName

        if (-not $inputMp4) {
            throw "add_BGM 用の mp4 が見つかりません"
        }

        Write-Host "add_BGM InputMp4 : $inputMp4"

        Run-PwshWithHeartbeat `
            -ScriptPath $bgmScript `
            -ScriptArgs @($inputMp4)
    }

}
catch {
    Write-Host "========================="
    Write-Host "[ERROR]"
    Write-Host $_
    Write-Host "========================="
    throw
}
finally {
    $TOTAL_SW.Stop()
    $TOTAL_END = NowString

    Write-Host "========================="
    Write-Host "[TOTAL]"
    Write-Host "開始時刻 : $TOTAL_START"
    Write-Host "終了時刻 : $TOTAL_END"
    Write-Host "総処理時間 : $($TOTAL_SW.Elapsed.TotalSeconds.ToString('0.0')) 秒 ($(Format-Elapsed $TOTAL_SW.Elapsed))"
    Write-Host "========================="
}
