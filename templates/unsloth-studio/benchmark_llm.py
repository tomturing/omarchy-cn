import time
import requests
import json
import sys
import os
from pathlib import Path

# 优先从环境变量或本地 ~/.config/litellm/config.yaml 读取真实配置，杜绝脚本硬编码敏感凭据
def load_local_config():
    base_url = os.getenv("NODE1_BASE_URL")
    api_key = os.getenv("NODE1_API_KEY")
    
    if not base_url or not api_key:
        cfg_path = Path.home() / ".config" / "litellm" / "config.yaml"
        if cfg_path.is_file():
            try:
                import yaml
                with open(cfg_path, "r", encoding="utf-8") as f:
                    data = yaml.safe_load(f)
                    for item in data.get("model_list", []):
                        params = item.get("litellm_params", {})
                        if "8888" in params.get("api_base", "") or "node1" in item.get("model_name", ""):
                            base_url = base_url or f"{params.get('api_base').rstrip('/')}/chat/completions"
                            api_key = api_key or params.get("api_key")
                            break
            except Exception:
                pass

    # 默认脱敏安全占位符
    base_url = base_url or "http://192.168.1.101:8888/v1/chat/completions"
    api_key = api_key or "sk-unsloth-node1-secret-token"
    return base_url, api_key

base_url, api_key = load_local_config()
headers = {
    "Authorization": f"Bearer {api_key}",
    "Content-Type": "application/json"
}

def benchmark(prompt_text, max_tokens=150, label="", thinking=False):
    payload = {
        "model": "unsloth-Qwen3.8-27B-Q8_0",
        "messages": [{"role": "user", "content": prompt_text}],
        "max_tokens": max_tokens,
        "temperature": 0.1,
        "stream": True,
        "stream_options": {"include_usage": True},
        "chat_template_kwargs": {"enable_thinking": thinking}
    }
    
    t0 = time.perf_counter()
    resp = requests.post(base_url, headers=headers, json=payload, stream=True, timeout=120)
    ttft = None
    first_token_time = None
    token_count = 0
    prompt_tokens = 0
    completion_tokens = 0
    
    for line in resp.iter_lines():
        if not line:
            continue
        line = line.decode("utf-8")
        if line.startswith("data: ") and not line.endswith("[DONE]"):
            chunk = json.loads(line[6:])
            choices = chunk.get("choices", [])
            if choices and choices[0].get("delta", {}).get("content"):
                if ttft is None:
                    first_token_time = time.perf_counter()
                    ttft = (first_token_time - t0) * 1000 # in ms
                token_count += 1
            if "usage" in chunk and chunk["usage"]:
                usage = chunk["usage"]
                prompt_tokens = usage.get("prompt_tokens", 0)
                completion_tokens = usage.get("completion_tokens", 0)
                
    t_end = time.perf_counter()
    gen_time = (t_end - first_token_time) if first_token_time else 0.001
    actual_tokens = completion_tokens if completion_tokens > 0 else token_count
    speed = actual_tokens / gen_time if gen_time > 0 else 0
    
    print(f"=== {label} ===")
    print(f"  输入 Prompt 长度: {prompt_tokens} tokens")
    print(f"  生成 Token 数: {actual_tokens} tokens")
    print(f"  TTFT (端到端首 Token 延迟): {ttft:.1f} ms" if ttft else "  TTFT: N/A")
    print(f"  生成总耗时: {gen_time:.2f} s")
    print(f"  生成速度 (Throughput): {speed:.2f} tokens/s")
    print()
    return {
        "label": label,
        "prompt_tokens": prompt_tokens,
        "completion_tokens": actual_tokens,
        "ttft_ms": ttft,
        "speed": speed
    }

if __name__ == "__main__":
    print(f"开始执行基准性能评测 (目标节点: {base_url})...\n")
    
    # 1. 短 Prompt (50~100 tokens)
    benchmark("请用一段话简述知识图谱在现代网络故障定位中的主要应用场景，100字左右。", max_tokens=150, label="1. 短 Prompt 场景 (~60 tokens)")
    
    # 2. 中等 Prompt (~500 tokens)
    med = "以下是网络故障排查手册片段：\n" + "在分布式SDN控制器环境中，BGP-EVPN负责在VTEP之间分发MAC/IP路由。当Underlay网络出现链路劣化、误码率升高或丢包时，会导致BGP Keepalive报文超时重传。若连续3次未收到KEEPALIVE报文，BGP邻居关系将被重置，进而引发大规模路由撤销与流量黑洞。排查此类故障时，首先需要确认Underlay各物理接口的CRC错包计数。\n" * 4 + "请提取上述手册中的关键故障现象及诱因。"
    benchmark(med, max_tokens=150, label="2. 中等 Prompt 场景 (~500 tokens)")
    
    # 3. 长 Prompt (~2000 tokens) - 模拟 Semantica 图谱抽取切片
    long_doc = "【虚拟化与网络排障手册节选】\n" + """
第1章：虚拟机启动失败排查规范
1.1 现象：调用Nova创建虚拟机接口返回500错误，日志显示NoValidHost。
1.2 排查：检查Placement服务资源余量，发现计算节点01的内存超分比例已达上限（RAM allocation ratio 1.5:1）。
1.3 解决：通过nova-compute配置文件调整分配比，或将负载迁移至其余具备充足资源的宿主机。
第2章：存储卷热挂载超时
2.1 现象：Cinder volume attach阶段在waiting-attach状态超时挂起。
2.2 排查：登录对应宿主机检查iscsiadm session，发现iSCSI发现阶段网络不可达，多路径软件multipathd报错无法激活路径。
2.3 解决：重启iscsid服务，修复物理存储网卡VLAN配置并刷新multipath设备。
""" * 8 + "请列出上述文档中包含的所有组件名称与处理动作。"
    benchmark(long_doc, max_tokens=150, label="3. 长 Prompt 知识抽取场景 (~2000 tokens)")

    # 4. 极端长 Prompt (~4000 tokens)
    huge_doc = long_doc * 2 + "请总结以上所有故障类型。"
    benchmark(huge_doc, max_tokens=150, label="4. 极长 Prompt 场景 (~4000 tokens)")
