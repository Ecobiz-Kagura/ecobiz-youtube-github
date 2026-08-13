param(
    [Parameter(Mandatory=$true)]
    [string]$Path,

    # 表示行数（任意）
    [int]$Lines = 100
)

# 候補エンコーディング（順番が重要）
$encList = @(
    @{ Name="utf8";    Enc="utf8" },
    @{ Name="utf8BOM"; Enc="utf8BOM" },
    @{ Name="sjis";    Enc="default" }, # Windows 日本語=CP932
    @{ Name="oem";     Enc="oem" }
)

function TryRead($file, $enc, $lines) {
    try {
        $text = Get-Content -LiteralPath $file -Encoding $enc -TotalCount $lines
        # 明らかに文字化けしている行（" " が多い）を避ける判定
        $joined = ($text -join "")
        if ($joined -match " {3,}") { return $null }
        return $text
    } catch {
        return $null
    }
}

# ---- 自動判定 & 表示 ----
foreach($item in $encList){
    $res = TryRead $Path $item.Enc $Lines
    if($res){
        Write-Host "=== Encoding Detected: $($item.Name) ===" -ForegroundColor Green
        $res | ForEach-Object { $_ }
        exit 0
    }
}

Write-Host "※どのエンコードでも読めませんでした。" -ForegroundColor Red
exit 1
