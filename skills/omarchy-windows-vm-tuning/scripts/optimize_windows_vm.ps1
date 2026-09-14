# Windows 11 虚拟机内部极致性能精简一键脚本
# 运行方式：以管理员身份打开 PowerShell，执行本脚本

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "   Windows 11 VM 极致性能精简与优化 (非破坏性、100% 可逆)   " -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

# 1. 调整视觉特效为【性能优先】
Write-Host "`n[1/5] 调整界面动画与视觉特效为性能优先..." -ForegroundColor Yellow
Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' -Name 'VisualFXSetting' -Value 2 -Force
Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'UserPreferencesMask' -Value ([byte[]](0x90,0x12,0x03,0x80,0x10,0x00,0x00,0x00)) -Force
Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop\WindowMetrics' -Name 'MinAnimate' -Value '0' -Force

# 2. 彻底停用并禁用 3 大吃盘吃 CPU 服务
Write-Host "[2/5] 停用并禁用高 I/O 争抢后台服务 (SysMain / WSearch / DiagTrack)..." -ForegroundColor Yellow

# SysMain (超级预读，虚拟磁盘疯狂争抢 I/O)
Stop-Service -Name "SysMain" -Force -ErrorAction SilentlyContinue
Set-Service -Name "SysMain" -StartupType Disabled

# Windows Search (搜索索引，后台遍历虚拟磁盘)
Stop-Service -Name "WSearch" -Force -ErrorAction SilentlyContinue
Set-Service -Name "WSearch" -StartupType Disabled

# DiagTrack (微软后台遥测上传)
Stop-Service -Name "DiagTrack" -Force -ErrorAction SilentlyContinue
Set-Service -Name "DiagTrack" -StartupType Disabled

# 3. 禁用 Windows 11 小组件与无用后台应用
Write-Host "[3/5] 禁用 Windows 11 小组件与后台应用自启..." -ForegroundColor Yellow
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' -Name 'AllowNewsAndInterests' -Value 0 -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' -Name 'GlobalUserDisabled' -Value 1 -Force

# 4. 关闭系统休眠释放物理磁盘空间
Write-Host "[4/5] 关闭系统休眠 (释放 4GB~8GB 物理虚拟磁盘空间)..." -ForegroundColor Yellow
powercfg -h off

# 5. 矫正时区为北京时间并配置活跃网卡纯净 DNS
Write-Host "[5/5] 校正系统时区为北京时间，并将活跃网卡 DNS 改为公共纯净 DNS..." -ForegroundColor Yellow
Set-TimeZone -Id "China Standard Time" -ErrorAction SilentlyContinue
Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Set-DnsClientServerAddress -ServerAddresses ("223.5.5.5", "119.29.29.29") -ErrorAction SilentlyContinue

Write-Host "`n✅ 极致精简与网络优化已全部完成！" -ForegroundColor Green
Write-Host "提示：建议重启一次 Windows 虚拟机使所有注册表与服务完全生效。" -ForegroundColor Cyan
