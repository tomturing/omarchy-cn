#!/usr/bin/env bash
# 利用 Btrfs 秒级 CoW 特性对 Windows VM 进行零成本快照备份与还原
set -euo pipefail

IMAGE="$HOME/.windows/data.img"
SNAPSHOT="$HOME/.windows/data.img.snapshot"

case "${1:-}" in
    backup)
        if [ ! -f "$IMAGE" ]; then
            echo "错误: 未在 $IMAGE 找到虚拟机磁盘镜像" >&2
            exit 1
        fi
        echo "正在利用 Btrfs reflink 创建秒级物理快照..."
        cp --reflink=always "$IMAGE" "$SNAPSHOT"
        echo "✅ 快照创建成功: $SNAPSHOT (0.1秒完成，零额外空间占用)"
        ;;
    restore)
        if [ ! -f "$SNAPSHOT" ]; then
            echo "错误: 未找到快照文件 $SNAPSHOT" >&2
            exit 1
        fi
        echo "⚠️ 正在回退还原虚拟机磁盘..."
        if pgrep -f "xfreerdp" >/dev/null 2>&1 || pgrep -f "qemu" >/dev/null 2>&1; then
            echo "正在停止 Windows 虚拟机..."
            omarchy-windows-vm stop 2>/dev/null || true
            sleep 2
        fi
        cp --reflink=always "$SNAPSHOT" "$IMAGE"
        echo "✅ 虚拟机磁盘已成功还原到快照版本！"
        echo "可运行 omarchy-windows-vm launch 重新启动。"
        ;;
    status)
        echo "=== 磁盘镜像与快照状态 ==="
        ls -lh "$IMAGE" "$SNAPSHOT" 2>/dev/null || true
        ;;
    *)
        echo "用法: $0 {backup|restore|status}"
        echo "  backup  - 创建秒级 CoW 快照备份 (不占额外磁盘空间)"
        echo "  restore - 从快照秒级回退还原虚拟机磁盘"
        echo "  status  - 查看当前镜像与快照信息"
        exit 1
        ;;
esac
