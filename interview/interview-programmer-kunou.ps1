# ディレクトリパスを指定
$directory = "D:\images_for_slide_show\プログラマー-苦悩"

$fileName_org = "10-programmer-kunou.mp4"

# １回
for ($i = 0; $i -lt 1; $i++) {


# ランダムに150個のファイルを選択
$randomFiles = Get-ChildItem -Path $directory -Filter "*.png" | Get-Random -Count 150

# ファイルパスを連結してffmpegに直接渡す
$fileList = ($randomFiles | ForEach-Object { $_.FullName }) -join "|"

#cd D:\images_for_slide_show\
#cd D:\

cp D:\ffmpeg.exe .


rm $fileName_org

Write-Host "fileName_org: $fileName_org"
Write-Host "Source File: $fileName_org.mp4"


# 早い
./ffmpeg -framerate 1/5 -t 2  -i "concat:$fileList" -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v libx264 -pix_fmt yuv420p $fileName_org
$tempFile = "D:\temp_$fileName_org_$((Get-Random).ToString()).mp4"

# ソースファイルを一時ファイルとしてコピー


Copy-Item -Path $fileName_org -Destination $tempFile

}

####

$storageDir = "D:\【エコビズ】\動画保管"   # 保管先ディレクトリ


# 現在の日時を取得（フォーマット: yyyyMMdd_HHmmss）
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

# 作成した動画を「動画保管」ディレクトリに移動（ファイル名に時刻を追加）
$finalFile = Join-Path $storageDir "$timestamp-$fileName_org"
Copy-Item -Path $tempFile -Destination $finalFile -Force

Write-Host "処理完了: 動画は $finalFile に保存されました。"


$storageDir = "D:\【エコビズ】\話の特集"   # 保管先ディレクトリ


# 現在の日時を取得（フォーマット: yyyyMMdd_HHmmss）
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

# 作成した動画を「動画保管」ディレクトリに移動（ファイル名に時刻を追加）
$finalFile = Join-Path $storageDir "$timestamp-$fileName_org"
Copy-Item -Path $tempFile -Destination $finalFile -Force

Write-Host "処理完了: 動画は $finalFile に保存されました。"


#cd D:\ecobiz-youtube-uploader\google-trans
#D:\ecobiz-youtube-uploader\google-trans\4x.ps1

