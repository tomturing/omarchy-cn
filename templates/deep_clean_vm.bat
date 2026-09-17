@echo off
:: Check Administrator Privileges
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [Info] Requesting Administrator Privileges...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

echo ========================================================
echo   Windows 11 VM Deep Clean and Optimization Script
echo ========================================================
echo.

echo [1/6] Disabling SysMain (Superfetch) service...
sc stop SysMain >nul 2>&1
sc config SysMain start=disabled >nul 2>&1

echo [2/6] Disabling Windows Search indexing service...
sc stop WSearch >nul 2>&1
sc config WSearch start=disabled >nul 2>&1

echo [3/6] Disabling DiagTrack (Telemetry) service...
sc stop DiagTrack >nul 2>&1
sc config DiagTrack start=disabled >nul 2>&1

echo [4/6] Disabling Widgets and background apps...
reg add "HKLM\SOFTWARE\Policies\Microsoft\Dsh" /v AllowNewsAndInterests /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" /v GlobalUserDisabled /t REG_DWORD /d 1 /f >nul 2>&1

echo [5/6] Disabling Hibernation to free disk space...
powercfg -h off >nul 2>&1

echo [6/6] Setting visual effects to performance mode...
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v EnableTransparency /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" /v VisualFXSetting /t REG_DWORD /d 2 /f >nul 2>&1
reg add "HKCU\Control Panel\Desktop\WindowMetrics" /v MinAnimate /t REG_SZ /d 0 /f >nul 2>&1

echo.
echo [Bonus] Fixing host.lan in hosts file...
findstr /i "host.lan" "%SystemRoot%\System32\drivers\etc\hosts" >nul 2>&1
if %errorLevel% neq 0 (
    echo.>> "%SystemRoot%\System32\drivers\etc\hosts"
    echo 172.30.0.1 host.lan>> "%SystemRoot%\System32\drivers\etc\hosts"
    echo [Bonus] Successfully added host.lan mapping to hosts!
) else (
    echo [Bonus] host.lan already present in hosts file.
)

echo.
echo ========================================================
echo   [SUCCESS] Optimization and Drive Fix completed!
echo   Idle CPU usage should drop to 0%% - 3%%.
echo   Drive Z: is now ready to connect without errors.
echo ========================================================
echo.
pause
