Get-ChildItem -File -Filter *.mp4 | ForEach-Object {
    Write-Host "•¶Žš‹N‚±‚µ’†: $($_.Name)"

    python -m whisper $_.FullName `
        --language Japanese `
        --model medium `
        --fp16 False `
        --output_format txt
}