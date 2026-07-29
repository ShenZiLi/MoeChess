#!/usr/bin/env python3
"""
从 codebase-memory-mcp 导出的 JSON 生成可视化 HTML 图谱。
- 节点: Function (按 file 分组着色)
- 边: CALLS
- 交互: 力导向布局、悬停显示 qualified_name、点击高亮邻居
"""
import json, os, html
from collections import defaultdict

GRAPH_DIR = "/workspace/.workbuddy/graph"

def load(name):
    with open(os.path.join(GRAPH_DIR, name)) as f:
        d = json.load(f)
    return d.get("rows", d.get("results", []))

calls = load("calls.json")
funcs = load("functions.json")
arch = json.load(open(os.path.join(GRAPH_DIR, "architecture.json")))

# 按文件包(目录)归类函数
pkg_of = {}
for f in funcs:
    name, qn, file = f[0], f[1], f[2] or ""
    # 提取 scripts/xxx 目录作为包
    parts = file.split("/")
    pkg = "root"
    if "scripts" in parts:
        i = parts.index("scripts")
        pkg = parts[i+1] if i+1 < len(parts) else "scripts"
    pkg_of[qn] = pkg

# 包颜色 (HSL)
packages = sorted(set(pkg_of.values()))
pkg_colors = {p: f"hsl({int(i*360/len(packages))},70%,55%)" for i,p in enumerate(packages)}

# 构建节点 (只保留出现过的函数, 限制 300 个以内避免浏览器卡)
qn_to_name = {f[1]: f[0] for f in funcs}
used = set()
for c in calls:
    used.add(c[1]); used.add(c[3])

# 优先保留核心包的节点
core_pkgs = ["core","ai","states","view","ui","debug","main_scene_controller","theme","input"]
def pkg_rank(qn):
    p = pkg_of.get(qn,"")
    return core_pkgs.index(p) if p in core_pkgs else 99

nodes_sorted = sorted(used, key=lambda q: (pkg_rank(q), qn_to_name.get(q,"")))
nodes = nodes_sorted[:300]
nodeset = set(nodes)

edges = [[c[1], c[3]] for c in calls if c[1] in nodeset and c[3] in nodeset]

# 计算 degree (用于节点大小)
deg = defaultdict(int)
for s,d in edges:
    deg[s]+=1; deg[d]+=1

nodes_json = []
for qn in nodes:
    name = qn_to_name.get(qn, qn.split(".")[-1])
    p = pkg_of.get(qn,"root")
    nodes_json.append({
        "id": qn,
        "label": name,
        "pkg": p,
        "color": pkg_colors[p],
        "size": 6 + min(deg[qn]*1.2, 18),
        "qn": qn,
    })

edges_json = [{"source": s, "target": d} for s,d in edges]

# 热点数据
hotspots = arch.get("hotspots", [])[:10]
clusters = arch.get("clusters", [])[:6]

stats = {
    "total_nodes": arch["total_nodes"],
    "total_edges": arch["total_edges"],
    "shown_nodes": len(nodes_json),
    "shown_edges": len(edges_json),
    "packages": packages,
    "pkg_colors": pkg_colors,
}

data = {
    "nodes": nodes_json,
    "edges": edges_json,
    "stats": stats,
    "hotspots": hotspots,
    "clusters": clusters,
}

html_doc = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<title>萌象棋 - 代码图谱可视化</title>
<style>
  body { margin:0; font-family:-apple-system,'Segoe UI',sans-serif; background:#0d1117; color:#c9d1d9; }
  #container { display:flex; height:100vh; }
  #sidebar { width:300px; padding:16px; background:#161b22; overflow-y:auto; border-right:1px solid #30363d; }
  #sidebar h1 { font-size:18px; margin:0 0 8px; color:#58a6ff; }
  #sidebar h2 { font-size:14px; margin:16px 0 6px; color:#79c0ff; border-bottom:1px solid #30363d; padding-bottom:4px; }
  .stat { font-size:12px; color:#8b949e; margin:2px 0; }
  .legend-item { display:flex; align-items:center; font-size:12px; margin:3px 0; }
  .legend-dot { width:10px; height:10px; border-radius:50%; margin-right:6px; }
  .hotspot { font-size:12px; margin:3px 0; padding:4px 6px; background:#21262d; border-radius:4px; }
  .hotspot b { color:#f0883e; }
  #graph { flex:1; }
  #tooltip { position:absolute; pointer-events:none; background:#1f2937; border:1px solid #58a6ff; padding:6px 10px; border-radius:4px; font-size:12px; display:none; max-width:400px; word-break:break-all; }
  #controls { position:absolute; top:10px; right:10px; background:#161b22; padding:8px; border-radius:6px; border:1px solid #30363d; font-size:12px; }
  button { background:#238636; color:white; border:0; padding:4px 10px; border-radius:4px; cursor:pointer; margin-right:4px; font-size:12px; }
  button.sec { background:#21262d; border:1px solid #30363d; }
  svg { width:100%; height:100%; }
  .node { cursor:pointer; }
  .node text { font-size:9px; pointer-events:none; fill:#8b949e; }
  .edge { stroke:#30363d; stroke-width:0.6; }
  .node-highlighted .edge-hl { stroke:#58a6ff; stroke-width:2; }
</style>
</head>
<body>
<div id="container">
  <div id="sidebar">
    <h1>萌象棋 代码图谱</h1>
    <div class="stat">项目: workspace (branch dev)</div>
    <div class="stat">总节点: <span id="t-nodes"></span> / 显示 <span id="s-nodes"></span></div>
    <div class="stat">总边数: <span id="t-edges"></span> / 显示 <span id="s-edges"></span></div>

    <h2>包 (颜色图例)</h2>
    <div id="legend"></div>

    <h2>热点函数 (高扇入)</h2>
    <div id="hotspots"></div>

    <h2>模块集群</h2>
    <div id="clusters"></div>
  </div>
  <div id="graph">
    <div id="controls">
      <button onclick="restart()">重排</button>
      <button class="sec" onclick="toggleLabels()">标签</button>
      <button class="sec" onclick="fitView()">居中</button>
    </div>
    <div id="tooltip"></div>
  </div>
</div>
<script src="https://d3js.org/d3.v7.min.js"></script>
<script>
const DATA = __DATA__;
document.getElementById('t-nodes').textContent = DATA.stats.total_nodes;
document.getElementById('s-nodes').textContent = DATA.stats.shown_nodes;
document.getElementById('t-edges').textContent = DATA.stats.total_edges;
document.getElementById('s-edges').textContent = DATA.stats.shown_edges;

const legend = document.getElementById('legend');
DATA.stats.packages.forEach(p => {
  const d = document.createElement('div'); d.className='legend-item';
  d.innerHTML = '<span class="legend-dot" style="background:'+DATA.stats.pkg_colors[p]+'"></span>'+p;
  legend.appendChild(d);
});

const hs = document.getElementById('hotspots');
DATA.hotspots.forEach(h => {
  const d = document.createElement('div'); d.className='hotspot';
  d.innerHTML = '<b>'+h.name+'</b> <span style="color:#8b949e">(fan-in '+h.fan_in+')</span><br><span style="color:#6e7681;font-size:10px">'+h.qualified_name+'</span>';
  hs.appendChild(d);
});

const cl = document.getElementById('clusters');
DATA.clusters.forEach(c => {
  const d = document.createElement('div'); d.className='hotspot';
  d.innerHTML = '<b>cluster #'+c.id+'</b> <span style="color:#8b949e">'+c.members+' nodes</span><br><span style="color:#6e7681;font-size:10px">'+c.top_nodes.slice(0,4).join(', ')+'</span>';
  cl.appendChild(d);
});

// 力导向图
const W = document.getElementById('graph').clientWidth;
const H = document.getElementById('graph').clientHeight;
const svg = d3.select('#graph').append('svg').attr('viewBox',`0 0 ${W} ${H}`);
const g = svg.append('g');
const link = g.append('g').attr('class','edges').selectAll('line').data(DATA.edges).enter().append('line').attr('class','edge');
const node = g.append('g').attr('class','nodes').selectAll('circle').data(DATA.nodes).enter().append('g').attr('class','node').call(d3.drag().on('start',dragstart).on('drag',dragged).on('end',dragend));
node.append('circle').attr('r',d=>d.size).attr('fill',d=>d.color).attr('stroke','#0d1117').attr('stroke-width',1);
const labels = node.append('text').text(d=>d.label).attr('dx', d=>d.size+2).attr('dy',3).style('display','none');

const sim = d3.forceSimulation(DATA.nodes)
  .force('link', d3.forceLink(DATA.edges).id(d=>d.id).distance(50).strength(0.3))
  .force('charge', d3.forceManyBody().strength(-80))
  .force('center', d3.forceCenter(W/2, H/2))
  .force('collide', d3.forceCollide().radius(d=>d.size+3));
sim.on('tick', () => {
  link.attr('x1',d=>d.source.x).attr('y1',d=>d.source.y).attr('x2',d=>d.target.x).attr('y2',d=>d.target.y);
  node.attr('transform', d=>`translate(${d.x},${d.y})`);
});

function dragstart(e,d){ if(!e.active) sim.alphaTarget(0.3).restart(); d.fx=d.x; d.fy=d.y; }
function dragged(e,d){ d.fx=e.x; d.fy=e.y; }
function dragend(e,d){ if(!e.active) sim.alphaTarget(0); d.fx=null; d.fy=null; }

const tooltip = document.getElementById('tooltip');
node.on('mouseover', (e,d) => {
  tooltip.style.display='block';
  tooltip.innerHTML = '<b style="color:'+d.color+'">'+d.label+'</b><br><span style="color:#8b949e">'+d.qn+'</span><br>pkg: '+d.pkg+' | size: '+d.size.toFixed(1);
  // 高亮邻居
  const neighbors = new Set([d.id]);
  DATA.edges.forEach(e => { if(e.source.id===d.id) neighbors.add(e.target.id); if(e.target.id===d.id) neighbors.add(e.source.id); });
  node.select('circle').attr('opacity', n => neighbors.has(n.id) ? 1 : 0.15);
  link.attr('stroke', e => (e.source.id===d.id||e.target.id===d.id) ? '#58a6ff' : '#30363d').attr('stroke-width', e => (e.source.id===d.id||e.target.id===d.id) ? 1.8 : 0.6);
}).on('mousemove', e => { tooltip.style.left=(e.pageX+12)+'px'; tooltip.style.top=(e.pageY+12)+'px'; }).on('mouseout', () => {
  tooltip.style.display='none';
  node.select('circle').attr('opacity',1);
  link.attr('stroke','#30363d').attr('stroke-width',0.6);
});

function restart(){ sim.alpha(1).restart(); }
let labelOn=false;
function toggleLabels(){ labelOn=!labelOn; labels.style('display', labelOn?'block':'none'); }
const zoom = d3.zoom().scaleExtent([0.2,4]).on('zoom', e => g.attr('transform', e.transform));
svg.call(zoom);
function fitView(){ svg.transition().duration(500).call(zoom.transform, d3.zoomIdentity); }
</script>
</body>
</html>
"""

html_doc = html_doc.replace("__DATA__", json.dumps(data, ensure_ascii=False))
out = "/workspace/.workbuddy/graph/codebase-graph.html"
with open(out, "w") as f:
    f.write(html_doc)
print(f"已生成: {out}")
print(f"节点: {len(nodes_json)} / 边: {len(edges_json)} / 包: {len(packages)}")
