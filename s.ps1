#ls | Where-Object { $_.Name -match "short" }
ls | Where-Object { $_.Extension -eq ".txt" -and $_.Name -match "short" }
#ls 2*