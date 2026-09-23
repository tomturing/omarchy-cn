<#
.SYNOPSIS
    Windows 22 节点 Unsloth Studio 本地/远程管理 PowerShell 脚本
.DESCRIPTION
    通过 Unsloth Studio REST API (/api/inference/load, status, unload)
    实现模型热加载、极限制批处理参数 (-b 8192 -ub 2048) 注入、显存状态查询与释放。
.EXAMPLE
    .\reload_windows_q8.ps1 -Action Load
    .\reload_windows_q8.ps1 -Action Status
    .\reload_windows_q8.ps1 -Action Unload
#>

[CmdletBinding()]
param (
    [Parameter(Position = 0)]
    [ValidateSet("Load", "Status", "System", "Unload", "Health")]
    [string]$Action = "Load",

    [string]$BaseUrl = "http://127.0.0.1:8080",
    [string]$ApiKey = "sk-unsloth-win22-masterkey",
    [string]$ModelPath = "unsloth/Qwen3.8-27B-GGUF",
    [string]$Quant = "Q8_0",
    [int]$MaxSeqLength = 131072,
    [int]$BatchSize = 8192,
    [int]$UbatchSize = 2048
)

$headers = @{
    "Authorization" = "Bearer $ApiKey"
    "Content-Type"  = "application/json"
    "Accept"        = "application/json"
}

switch ($Action) {
    "Status" {
        Write-Host "==> 查询 Unsloth Studio 推理状态 ($BaseUrl)..." -ForegroundColor Cyan
        try {
            $resp = Invoke-RestMethod -Uri "$BaseUrl/api/inference/status" -Method Get -Headers $headers
            $resp | ConvertTo-Json -Depth 5
        } catch {
            Write-Error "请求失败: $_"
        }
    }

    "System" {
        Write-Host "==> 查询 Windows 宿主机硬件资源状态 ($BaseUrl)..." -ForegroundColor Cyan
        try {
            $resp = Invoke-RestMethod -Uri "$BaseUrl/api/system/status" -Method Get -Headers $headers
            $resp | ConvertTo-Json -Depth 5
        } catch {
            Write-Error "请求失败: $_"
        }
    }

    "Health" {
        Write-Host "==> 探活检测: $BaseUrl/api/inference/status" -ForegroundColor Cyan
        try {
            $resp = Invoke-WebRequest -Uri "$BaseUrl/api/inference/status" -Method Get -Headers $headers -UseBasicParsing
            if ($resp.StatusCode -eq 200) {
                Write-Host "✅ 远端推理服务健康 (HTTP 200)" -ForegroundColor Green
            }
        } catch {
            Write-Error "❌ 探活失败: $_"
        }
    }

    "Unload" {
        Write-Host "==> 正在卸载模型以释放显存 ($BaseUrl)..." -ForegroundColor Yellow
        try {
            $resp = Invoke-RestMethod -Uri "$BaseUrl/api/inference/unload" -Method Post -Headers $headers
            Write-Host "✅ 卸载成功，显存已释放" -ForegroundColor Green
            $resp | ConvertTo-Json -Depth 3
        } catch {
            Write-Error "卸载失败: $_"
        }
    }

    "Load" {
        Write-Host "==> 开始向 Unsloth Studio 发送热加载请求..." -ForegroundColor Cyan
        Write-Host "    - 模型: $ModelPath ($Quant)"
        Write-Host "    - 上下文: $MaxSeqLength"
        Write-Host "    - 批处理参数: -b $BatchSize -ub $UbatchSize"

        $body = @{
            model_path       = $ModelPath
            gguf_variant     = $Quant
            max_seq_length   = $MaxSeqLength
            cache_type_k     = "q4_0"
            cache_type_v     = "q4_0"
            gpu_memory_mode  = "manual"
            gpu_layers       = 99
            llama_extra_args = @("-b", "$BatchSize", "-ub", "$UbatchSize")
        } | ConvertTo-Json

        try {
            $resp = Invoke-RestMethod -Uri "$BaseUrl/api/inference/load" -Method Post -Headers $headers -Body $body
            Write-Host "✅ 模型热加载成功 (HTTP 200)！" -ForegroundColor Green
            $resp | ConvertTo-Json -Depth 5
        } catch {
            Write-Error "❌ 加载失败: $_"
        }
    }
}
