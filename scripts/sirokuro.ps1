$TargetDir = "D:\images_for_slide_show\‚¶‚å‚ä‚¤-íŒã\“®‰æ"

Get-ChildItem -LiteralPath $TargetDir -File -Filter *.mp4 |
Where-Object { $_.BaseName -notlike "*_bw" } |
ForEach-Object {

    $input  = $_.FullName
    $output = Join-Path $_.DirectoryName ($_.BaseName + "_bw.mp4")

    Write-Host "----------------------------------------"
    Write-Host "”’•‰»’†: $($_.Name)"
    Write-Host "“ü—Í    : $input"
    Write-Host "o—Í    : $output"

    ffmpeg -y `
        -i "$input" `
        -vf "hue=s=0" `
        -c:v libx264 `
        -crf 18 `
        -preset medium `
        -c:a copy `
        "$output"

    if ($LASTEXITCODE -eq 0) {
        Write-Host "Š®—¹: $output"
    }
    else {
        Write-Host "ƒGƒ‰[: $input"
    }
}