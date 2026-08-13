$src = 'C:\Users\user\OneDrive\＊【エコビズ】\today'
$dest = Get-Location

Get-ChildItem $src -File -Recurse |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 4 |
    ForEach-Object {
        Copy-Item $_.FullName -Destination $dest -Force
        Write-Host "Copied: $($_.Name)"
    }
