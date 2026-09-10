$RootDir = "D:\images_for_slide_show"

# 保存先
$OutputFile = "C:\Users\user\OneDrive\directory_list.txt"

# 既存ファイルを初期化
Set-Content -LiteralPath $OutputFile -Value "" -Encoding UTF8

Write-Host "検索元:"
Write-Host $RootDir
Write-Host ""

Write-Host "保存先:"
Write-Host $OutputFile
Write-Host ""

$count = 0

Get-ChildItem -LiteralPath $RootDir -Directory -ErrorAction SilentlyContinue |
ForEach-Object {

    $count++

    # フルパス
    $dirName = $_.FullName

    # 途中経過を画面表示
    Write-Host ("[{0}] {1}" -f $count, $dirName)

    # 1件ずつ即時保存
    Add-Content -LiteralPath $OutputFile -Value $dirName -Encoding UTF8
}

Write-Host ""
Write-Host "完了しました。"
Write-Host "ディレクトリ数: $count"
Write-Host "保存先: $OutputFile"