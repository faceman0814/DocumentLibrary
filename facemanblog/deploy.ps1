param(
    [string]$commitMessage = "博客更新"
)

# 输出部署更新信息
Write-Host "正在部署到GitHub..." -ForegroundColor Green

# 构建项目
& hugo

# 进入Public文件夹
Set-Location public

# 扫描所有文件并替换指定字符串
$replacements = @{
    "https://github.com/faceman0814%25!%28EXTRA%20%3cnil%3e%29" = "https://github.com/faceman0814";
    "最近 Posts" = "最近博客";
}

# 扫描所有文件并替换指定字符串
Get-ChildItem -Recurse | Where-Object { !$_.PSIsContainer } | ForEach-Object {
    $content = Get-Content $_.FullName -Raw
    foreach ($oldText in $replacements.Keys) {
        $newText = $replacements[$oldText]
        $content = $content -replace [regex]::Escape($oldText), $newText
    }
    Set-Content $_.FullName -Value $content
}

# 复制 images 文件夹
$sourcePath = "D:\HugoWebsite\facemanblog\static\images"
$destinationPath = "D:\HugoWebsite\facemanblog\public\images"
Copy-Item -Path $sourcePath\* -Destination $destinationPath -Force -Recurse

# 将更改添加到git
git add .

# 提交更改
Write-Host $commitMessage -ForegroundColor Green
git commit -m $commitMessage

# 拉取最新的远程仓库更改以避免冲突
git pull origin main

# 推送源和构建仓库
git push origin main

# 返回到项目根目录
Set-Location ..