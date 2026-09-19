# Windows Defender 防火墙放行脚本（全 Profile 适用）
New-NetFirewallRule -DisplayName "llama-server-8080" `
                    -Direction Inbound `
                    -LocalPort 8080 `
                    -Protocol TCP `
                    -Action Allow `
                    -Profile Any `
                    -Force
Write-Host "[+] 8080 端口入站规则创建完毕，请确保 Unsloth 启动时带 -H 0.0.0.0 参数。" -ForegroundColor Green
