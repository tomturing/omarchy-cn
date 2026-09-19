import json
from pathlib import Path

def generate_visualizer(kg_json_path, output_html_path):
    with open(kg_json_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    entities = data.get("entities", [])
    relationships = data.get("relationships", [])

    color_palette = {
        "组件": "#3B82F6",       # 蓝
        "故障现象": "#EF4444",   # 红
        "排障动作": "#10B981",   # 绿
        "指标参数": "#F59E0B",   # 橙
        "命令工具": "#8B5CF6",   # 紫
        "默认": "#6B7280"
    }

    # Build node and edge data for vis-network
    nodes = []
    node_degrees = {}
    for r in relationships:
        s = r.get("source")
        t = r.get("target")
        node_degrees[s] = node_degrees.get(s, 0) + 1
        node_degrees[t] = node_degrees.get(t, 0) + 1

    for e in entities:
        name = e.get("name") or e.get("id")
        etype = e.get("type") or "默认"
        deg = node_degrees.get(name, 1)
        size = min(40, max(14, 12 + deg * 2))
        color = color_palette.get(etype, color_palette["默认"])
        nodes.append({
            "id": name,
            "label": name,
            "group": etype,
            "value": deg,
            "size": size,
            "color": {
                "background": color,
                "border": "#FFFFFF",
                "highlight": {"background": "#FBBF24", "border": "#B45309"}
            },
            "font": {"color": "#1F2937", "size": 13, "face": "system-ui, sans-serif"}
        })

    edges = []
    for i, r in enumerate(relationships):
        s = r.get("source")
        t = r.get("target")
        rel_type = r.get("type") or "related"
        edges.append({
            "id": f"e_{i}",
            "from": s,
            "to": t,
            "label": rel_type,
            "arrows": "to",
            "font": {"size": 10, "align": "middle", "color": "#6B7280"},
            "color": {"color": "#CBD5E1", "highlight": "#F59E0B"},
            "smooth": {"type": "curvedCW", "roundness": 0.15}
        })

    html_content = f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <title>运维知识图谱交互全景图 - 虚拟机开关机排障手册</title>
    <script src="https://unpkg.com/vis-network/standalone/umd/vis-network.min.js"></script>
    <style>
        * {{ box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }}
        body {{ display: flex; height: 100vh; overflow: hidden; background: #F8FAFC; color: #1E293B; }}
        #sidebar {{ width: 340px; background: #FFFFFF; border-right: 1px solid #E2E8F0; display: flex; flex-direction: column; z-index: 10; box-shadow: 2px 0 8px rgba(0,0,0,0.04); }}
        .header {{ padding: 18px 20px; border-bottom: 1px solid #E2E8F0; background: #F1F5F9; }}
        .header h1 {{ font-size: 16px; font-weight: 700; color: #0F172A; }}
        .header p {{ font-size: 12px; color: #64748B; margin-top: 4px; }}
        .controls {{ padding: 16px 20px; border-bottom: 1px solid #E2E8F0; }}
        .search-box {{ position: relative; margin-bottom: 12px; }}
        .search-box input {{ width: 100%; padding: 8px 12px; border: 1px solid #CBD5E1; border-radius: 6px; font-size: 13px; outline: none; }}
        .search-box input:focus {{ border-color: #3B82F6; box-shadow: 0 0 0 2px rgba(59,130,246,0.15); }}
        .legend {{ display: flex; flex-wrap: wrap; gap: 8px; margin-top: 8px; }}
        .legend-item {{ display: flex; align-items: center; font-size: 12px; font-weight: 500; cursor: pointer; padding: 3px 8px; border-radius: 12px; border: 1px solid transparent; }}
        .legend-color {{ width: 10px; height: 10px; border-radius: 50%; margin-right: 6px; }}
        .btn-group {{ display: flex; gap: 8px; margin-top: 12px; }}
        .btn {{ flex: 1; padding: 6px 10px; font-size: 12px; font-weight: 600; border: 1px solid #CBD5E1; background: #F8FAFC; border-radius: 6px; cursor: pointer; }}
        .btn:hover {{ background: #E2E8F0; }}
        .btn-primary {{ background: #3B82F6; color: #FFFFFF; border-color: #3B82F6; }}
        .btn-primary:hover {{ background: #2563EB; }}
        #details {{ flex: 1; overflow-y: auto; padding: 16px 20px; font-size: 13px; }}
        .detail-card {{ background: #F8FAFC; border: 1px solid #E2E8F0; border-radius: 8px; padding: 12px; margin-bottom: 12px; }}
        .detail-title {{ font-size: 14px; font-weight: 700; color: #0F172A; margin-bottom: 6px; }}
        .detail-badge {{ display: inline-block; padding: 2px 8px; font-size: 11px; border-radius: 4px; color: #FFF; margin-bottom: 8px; }}
        .rel-list {{ list-style: none; margin-top: 6px; }}
        .rel-list li {{ padding: 4px 0; border-bottom: 1px dashed #E2E8F0; font-size: 12px; }}
        .rel-badge {{ color: #2563EB; font-weight: 600; margin-right: 4px; }}
        #network-container {{ flex: 1; height: 100%; position: relative; }}
        #network {{ width: 100%; height: 100%; }}
        .tip-banner {{ position: absolute; top: 16px; right: 16px; background: rgba(15, 23, 42, 0.85); color: #FFF; padding: 10px 16px; border-radius: 8px; font-size: 12px; pointer-events: none; }}
    </style>
</head>
<body>
    <div id="sidebar">
        <div class="header">
            <h1>运维知识图谱全景浏览器</h1>
            <p>基于 Qwen3.8-27B 抽取 (414 实体 · 618 关系)</p>
        </div>
        <div class="controls">
            <div class="search-box">
                <input type="text" id="searchInput" placeholder="搜索实体名称 (如: CPU, 开机, KVM)..." onkeyup="searchNode()">
            </div>
            <div class="legend">
                <div class="legend-item" style="background:#EFF6FF;" onclick="filterGroup('组件')"><span class="legend-color" style="background:#3B82F6;"></span>组件 (200)</div>
                <div class="legend-item" style="background:#FEF2F2;" onclick="filterGroup('故障现象')"><span class="legend-color" style="background:#EF4444;"></span>故障现象 (213)</div>
                <div class="legend-item" style="background:#ECFDF5;" onclick="filterGroup('排障动作')"><span class="legend-color" style="background:#10B981;"></span>排障动作 (156)</div>
                <div class="legend-item" style="background:#FFFBEB;" onclick="filterGroup('指标参数')"><span class="legend-color" style="background:#F59E0B;"></span>指标参数 (122)</div>
                <div class="legend-item" style="background:#F5F3FF;" onclick="filterGroup('命令工具')"><span class="legend-color" style="background:#8B5CF6;"></span>命令工具 (53)</div>
            </div>
            <div class="btn-group">
                <button class="btn btn-primary" onclick="fitView()">适合窗口</button>
                <button class="btn" onclick="togglePhysics()">固定/自由布局</button>
                <button class="btn" onclick="resetFilter()">重置高亮</button>
            </div>
        </div>
        <div id="details">
            <p style="color:#64748B; text-align:center; margin-top:40px;">点击图中任意节点，<br>查看关联因果链路与排障动作</p>
        </div>
    </div>
    <div id="network-container">
        <div id="network"></div>
        <div class="tip-banner">
            💡 滚轮缩放 · 拖拽画布 · 单击节点高亮关联链路
        </div>
    </div>

    <script>
        const rawNodes = {json.dumps(nodes, ensure_ascii=False)};
        const rawEdges = {json.dumps(edges, ensure_ascii=False)};

        const nodes = new vis.DataSet(rawNodes);
        const edges = new vis.DataSet(rawEdges);

        const container = document.getElementById('network');
        const data = {{ nodes: nodes, edges: edges }};
        const options = {{
            nodes: {{
                shape: 'dot',
                borderWidth: 1.5,
                shadow: true
            }},
            edges: {{
                width: 1.2,
                arrows: {{ to: {{ enabled: true, scaleFactor: 0.6 }} }},
                selectionWidth: 2.5
            }},
            physics: {{
                solver: 'forceAtlas2Based',
                forceAtlas2Based: {{
                    gravitationalConstant: -38,
                    centralGravity: 0.005,
                    springLength: 80,
                    springConstant: 0.12,
                    damping: 0.75
                }},
                stabilization: {{
                    iterations: 120,
                    updateInterval: 25
                }}
            }},
            interaction: {{
                hover: true,
                tooltipDelay: 100,
                hideEdgesOnDrag: true
            }}
        }};

        const network = new vis.Network(container, data, options);
        let physicsEnabled = true;

        network.on("click", function (params) {{
            if (params.nodes.length > 0) {{
                const nodeId = params.nodes[0];
                showNodeDetails(nodeId);
                highlightNeighbors(nodeId);
            }} else {{
                resetFilter();
            }}
        }});

        function showNodeDetails(nodeId) {{
            const node = rawNodes.find(n => n.id === nodeId);
            const connectedEdges = network.getConnectedEdges(nodeId);
            let inRels = [];
            let outRels = [];

            connectedEdges.forEach(eId => {{
                const e = rawEdges.find(item => item.id === eId);
                if (e) {{
                    if (e.from === nodeId) {{
                        outRels.push(`<li><span class="rel-badge">--[${{e.label}}]-></span> ${{e.to}}</li>`);
                    }} else {{
                        inRels.push(`<li><span class="rel-badge"><-[${{e.label}}]--</span> ${{e.from}}</li>`);
                    }}
                }}
            }});

            const badgeBg = node.color.background;
            let html = `
                <div class="detail-card">
                    <div class="detail-title">${{node.label}}</div>
                    <span class="detail-badge" style="background:${{badgeBg}}">${{node.group}}</span>
                    <div style="font-size:12px; color:#64748B;">关联链路总数: ${{connectedEdges.length}}</div>
                </div>
            `;

            if (outRels.length > 0) {{
                html += `
                    <div class="detail-card">
                        <div style="font-weight:600; margin-bottom:4px; font-size:12px; color:#475569;">引发/指向的后续实体:</div>
                        <ul class="rel-list">${{outRels.join("")}}</ul>
                    </div>
                `;
            }}

            if (inRels.length > 0) {{
                html += `
                    <div class="detail-card">
                        <div style="font-weight:600; margin-bottom:4px; font-size:12px; color:#475569;">前驱因果/关联实体:</div>
                        <ul class="rel-list">${{inRels.join("")}}</ul>
                    </div>
                `;
            }}

            document.getElementById("details").innerHTML = html;
        }}

        function highlightNeighbors(nodeId) {{
            const connectedNodes = network.getConnectedNodes(nodeId);
            connectedNodes.push(nodeId);

            const updateArray = rawNodes.map(n => {{
                if (connectedNodes.includes(n.id)) {{
                    return {{ id: n.id, hidden: false, opacity: 1 }};
                }} else {{
                    return {{ id: n.id, hidden: false, opacity: 0.15 }};
                }}
            }});
            nodes.update(updateArray);
        }}

        function resetFilter() {{
            const updateArray = rawNodes.map(n => ({{ id: n.id, hidden: false, opacity: 1 }}));
            nodes.update(updateArray);
            document.getElementById("details").innerHTML = '<p style="color:#64748B; text-align:center; margin-top:40px;">点击图中任意节点，<br>查看关联因果链路与排障动作</p>';
        }}

        function searchNode() {{
            const val = document.getElementById('searchInput').value.trim().toLowerCase();
            if (!val) {{
                resetFilter();
                return;
            }}
            const match = rawNodes.find(n => n.id.toLowerCase().includes(val));
            if (match) {{
                network.focus(match.id, {{ scale: 1.2, animation: true }});
                showNodeDetails(match.id);
                highlightNeighbors(match.id);
            }}
        }}

        function filterGroup(groupName) {{
            const updateArray = rawNodes.map(n => ({{
                id: n.id,
                hidden: n.group !== groupName
            }}));
            nodes.update(updateArray);
            fitView();
        }}

        function fitView() {{
            network.fit({{ animation: {{ duration: 500 }} }});
        }}

        function togglePhysics() {{
            physicsEnabled = !physicsEnabled;
            network.setOptions({{ physics: {{ enabled: physicsEnabled }} }});
        }}
    </script>
</body>
</html>
"""
    Path(output_html_path).write_text(html_content, encoding="utf-8")
    print(f"[visualizer] generated interactive viewer at {output_html_path}")

if __name__ == "__main__":
    generate_visualizer("kb_out_win_qwen38/kg.json", "kb_out_win_qwen38/index.html")
