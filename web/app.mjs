import {segmentEditor} from './segments.mjs';
import {renderDiagnostics} from './diagnostics.mjs';
const $ = id => document.getElementById(id);
let worker, timer, latest, latestInput, ready = false;
let epoch = 0, sequence = 0, pending, revision = 0, degraded = false;
let selectedEvidence;
let validationPending;
const editor = segmentEditor((input, callback) => {
  if (!ready) return;
  const id = ++sequence;
  validationPending = {id,callback};
  worker.postMessage({id,kind:'validate',input});
}, () => {revision++; if(latest)setStatus('参数已修改，请重新计算。');});
const buttons = [$('analyze'), $('search')];
function busy(value) { for (const b of buttons) b.disabled = value; }
function setStatus(message, error = false) { $('status').textContent = message; $('status').className = error ? 'bad' : 'good'; }
function receive(data, generation) {
  if (generation !== epoch) return;
  if (data.ready) {
    const limits = data.contract.limits;
    $('resolution').min = limits.resolution_min; $('resolution').max = limits.json_resolution_max;
    $('intervals').max = limits.search_intervals_max;
    $('base').min = limits.base_radius_min; $('base').max = limits.geometry_length_max;
    $('roller').max = limits.geometry_length_max;
    $('compare-sampling').disabled = degraded;
    if (degraded) $('compare-sampling').checked = false;
    $('compatibility-notice').hidden = !degraded;
    ready = true; editor.setLimit(limits.segments_max); editor.check(); busy(false); setStatus(degraded ? '兼容模式：MoonBit 引擎在主线程运行，计算期间页面可能暂停响应。' : '计算引擎已就绪'); return; }
  if (validationPending?.id === data.id) {
    const task = validationPending; validationPending = undefined;
    task.callback(data.response || {ok:false,error:data.error}); return;
  }
  if (!pending || data.id !== pending.id) return;
  const task = pending; pending = undefined;
  clearTimeout(timer); busy(false);
  for (const b of document.querySelectorAll('[data-export]')) b.disabled = !latest;
  if (data.error || !data.response?.ok) { if(task.kind !== 'export') editor.check(); setStatus(data.error || `${data.response.field ? data.response.field + '：' : ''}${data.response.error}`, true); return; }
  if (task.kind === 'export') { download(`mooncam.${task.format}`, data.response.content, task.format === 'svg' ? 'image/svg+xml' : 'text/plain'); return; }
  latest = data.response; render();
  setStatus(latest.result.sampled_feasible ? '采样局部约束通过，轮廓交叉检查完成且未发现交叉。' : '采样约束不满足、发现轮廓交叉或检查无法确定，请查看各项状态。', !latest.result.sampled_feasible);
  if (latest.tested) $('status').append(document.createTextNode(` 已检查 ${latest.tested} 个网格位置，步长 ${latest.grid_step_mm.toFixed(3)} mm；结果不代表全局最小尺寸。`));
  if (revision !== task.revision) setStatus('参数在计算期间发生变化；图表和下载对应提交时的参数，请重新计算。', true);
}
async function fallback(generation) {
  try {
    const engine = await import('./engine.js');
    if (generation !== epoch) return;
    degraded = true;
    worker = {postMessage(task) { queueMicrotask(() => {
      if (generation !== epoch) return;
      try { receive({id: task.id, response: JSON.parse(task.kind === 'validate' ? engine.validate_segments(task.input) : task.kind === 'export' ? engine.export_profile(task.format) : engine.run(task.input))}, generation); }
      catch (error) { receive({id: task.id, error: error.message}, generation); }
    }); }, terminate() {}};
    receive({ready: true, contract: JSON.parse(engine.contract())}, generation);
  } catch (error) { if (generation === epoch) setStatus(`引擎加载失败：${error.message}。请执行 npm run build 并通过 HTTP 服务访问。`, true); }
}
function startWorker() {
  ready = false; pending = undefined; degraded = false;
  const generation = ++epoch;
  try {
    worker = new Worker(new URL('./worker.mjs', import.meta.url), {type: 'module'});
    worker.onmessage = ({data}) => receive(data, generation);
    worker.onerror = () => {
      if (generation !== epoch) return;
      clearTimeout(timer); worker.terminate(); latest = undefined;
      for (const b of document.querySelectorAll('[data-export]')) b.disabled = true;
      pending = undefined; fallback(++epoch);
    };
  } catch { fallback(generation); }
}
function dispatch(task) {
  const id = ++sequence;
  pending = {...task, id, revision}; busy(true);
  for (const b of document.querySelectorAll('[data-export]')) b.disabled = true;
  if (!degraded) timer = setTimeout(() => {
    worker.terminate(); latest = undefined; startWorker();
    setStatus('计算超过 20 秒，已停止并重建引擎。请降低采样数或搜索区间数后重试。', true);
  }, 20000);
  worker.postMessage({...task, id});
}
function configuration(action) {
  const segments = editor.values();
  return {action, units:'mm', compare_sampling:!degraded && $('compare-sampling').checked, base_radius_mm:Number($('base').value), roller_radius_mm:Number($('roller').value), offset_mm:Number($('offset').value), rpm:Number($('rpm').value), pressure_limit_deg:Number($('limit').value), resolution:Number($('resolution').value), segments,
    ...(action === 'search' ? {search:{lower_mm:Number($('lower').value),upper_mm:Number($('upper').value),intervals:Number($('intervals').value)}} : {})};
}
function calculate(action) {
  if (!ready) return;
  try {
    latestInput=configuration(action);
    const input = JSON.stringify({...latestInput,outputs:['points'],include_input:false});
    latest = undefined; selectedEvidence = undefined;
    for (const id of ['metrics','profile','chart','diagnostics','evidence','comparison']) $(id).replaceChildren();
    $('comparison-panel').hidden = true;
    $('sampling').textContent = ''; $('range').textContent = ''; $('angle').value = '0.0°';
    for(const b of document.querySelectorAll('[data-export]')) b.disabled=true;
    busy(true); setStatus('正在计算…');
    dispatch({kind: 'calculate', input});
  } catch (error) {busy(false); setStatus(`输入格式错误：${error.message}`, true);}
}
function metric(title, value, status='') {
  const box = document.createElement('div'); box.className = 'metric';
  const label = document.createElement('span'); label.textContent = title;
  const strong = document.createElement('strong'); strong.textContent = value; strong.className = status;
  box.append(label,strong); return box;
}
function render() {
  const r = latest.result;
  selectedEvidence = undefined;
  $('metrics').replaceChildren(metric('综合采样检查',r.sampled_feasible?'满足约束':r.state==='incomplete'?'检查未完成':'需调整',r.sampled_feasible?'good':'bad'),metric('最大压力角',`${r.max_pressure_deg.toFixed(2)}°`),metric('当前基圆半径',`${r.base_radius_mm.toFixed(2)} mm`),metric('轮廓交叉检查',r.crossing_check.status==='complete'?`${r.crossing_check.count} 处`:r.crossing_check.status==='indeterminate'?'无法确定':'未完成',r.crossing_check.status==='complete'&&r.crossing_check.count===0?'good':'bad'));
  // Construct display elements from numeric results; downloaded SVG remains MoonBit-generated.
  const ns = 'http://www.w3.org/2000/svg';
  const image = document.createElementNS(ns, 'svg');
  let extent = 1;
  for (const p of r.points) extent = Math.max(extent, Math.abs(p.x), Math.abs(p.y), Math.abs(p.pitch_x) + r.roller_radius_mm, Math.abs(p.pitch_y) + r.roller_radius_mm);
  const margin = extent * 1.15;
  image.setAttribute('viewBox', `${-margin} ${-margin} ${margin*2} ${margin*2}`);
  image.setAttribute('role', 'img'); image.setAttribute('aria-label', '凸轮接触轮廓');
  const line = document.createElementNS(ns, 'polyline');
  line.setAttribute('points', r.points.map(p => `${p.x},${-p.y}`).join(' '));
  line.setAttribute('fill', 'none'); line.setAttribute('stroke', '#087f8c'); line.setAttribute('stroke-width', extent*.008);
  image.append(line); $('profile').replaceChildren(image);
  const circle = document.createElementNS('http://www.w3.org/2000/svg','circle');
  circle.id = 'roller-marker'; circle.setAttribute('r',r.roller_radius_mm); circle.setAttribute('fill','#e7a44a66'); circle.setAttribute('stroke','#c17c1c'); circle.setAttribute('stroke-width',Math.max(.1,r.roller_radius_mm/10));
  $('profile').firstElementChild.append(circle);
  $('sampling').textContent=`每圈目标分辨率 ${r.sampling.nominal_resolution}，实际区间 ${r.sampling.actual_intervals}，含闭合点共 ${r.sampling.sample_count} 点。`;
  $('phase').max = r.points.length-1; $('phase').value = 0;
  for (const button of document.querySelectorAll('[data-export]')) button.disabled = false;
  renderDiagnostics(r, selectLocation, selectEvidence);
  chart(); phase();
}
function phase() {
  if (!latest) return;
  const p = latest.result.points[Number($('phase').value)];
  $('angle').value = `${(p.theta_rad*180/Math.PI).toFixed(1)}°`;
  $('roller-marker').setAttribute('cx',p.pitch_x); $('roller-marker').setAttribute('cy',-p.pitch_y);
  highlight(p);
  $('angle').title = `第 ${p.segment_index+1} 段 · 点 ${p.sample_index}`;
  $('phase').setAttribute('aria-label', `第 ${p.segment_index+1} 段 · 点 ${p.sample_index}`);
}
function chart() {
  if (!latest) return;
  const key = $('trace').value, points = latest.result.points;
  let low = 0, high = 0;
  for (const p of points) {low=Math.min(low,p[key]);high=Math.max(high,p[key]);}
  const span=high-low||1;
  const path = points.map((p,i)=>`${i?'L':'M'}${(20+p.theta_rad/(2*Math.PI)*660).toFixed(2)},${(195-(p[key]-low)/span*175).toFixed(2)}`).join(' ');
  const line = document.createElementNS('http://www.w3.org/2000/svg','path');line.setAttribute('d',path);line.setAttribute('fill','none');line.setAttribute('stroke','#087f8c');line.setAttribute('stroke-width','2');
  $('chart').replaceChildren(line);
  $('range').textContent=`横轴 0° → 360°；纵轴 ${low.toFixed(3)} → ${high.toFixed(3)}。有限跃度跳变 ${latest.result.jerk_jumps} 处。曲线按采样点连线。`;
  const p = points[Number($('phase').value)]; drawCursor(p);
}

function svgNode(tag, attributes) {
  const node = document.createElementNS('http://www.w3.org/2000/svg',tag);
  for (const [key,value] of Object.entries(attributes)) node.setAttribute(key,value);
  return node;
}
function drawCursor(point) {
  $('chart-cursor')?.remove();
  if (!point || !$('chart').firstElementChild) return;
  const x = 20 + point.theta_rad/(2*Math.PI)*660;
  $('chart').append(svgNode('line',{id:'chart-cursor',x1:x,x2:x,y1:12,y2:205,stroke:'#ba4a2d','stroke-width':1.5,'stroke-dasharray':'4 3','data-sample-index':point.sample_index}));
}
function highlight(point) {
  $('selection-layer')?.remove();
  const image = $('profile').firstElementChild;
  if (!image) return;
  const width = Number(image.getAttribute('viewBox').split(' ')[2]);
  const layer = svgNode('g',{id:'selection-layer','pointer-events':'none'});
  const points = latest.result.points;
  // Owning segment IDs come from MoonBit; include each edge's end at a boundary.
  const selected = [];
  for (let i=0;i<points.length-1;i++) if (points[i].segment_index === point.segment_index) {
    if (!selected.length) selected.push(points[i]); selected.push(points[i+1]);
  }
  layer.append(svgNode('polyline',{points:selected.map(p=>`${p.x},${-p.y}`).join(' '),fill:'none',stroke:'#d59428','stroke-width':width*.007,'data-segment-index':point.segment_index}));
  if (selectedEvidence) for (const [index,edge] of [selectedEvidence.edge_a,selectedEvidence.edge_b].entries()) {
    layer.append(svgNode('line',{x1:edge.start_x,y1:-edge.start_y,x2:edge.end_x,y2:-edge.end_y,stroke:index?'#843ca4':'#007a87','stroke-width':width*.012,'data-edge-index':edge.edge_index,class:'witness-edge'}));
  }
  layer.append(svgNode('circle',{cx:point.x,cy:-point.y,r:width*.009,fill:'#ba4a2d','data-sample-index':point.sample_index,id:'contact-marker'}));
  image.append(layer); drawCursor(point);
}
function selectLocation(location, trace) {
  const point = latest?.result.points[location.sample_index];
  if (!point || point.segment_index !== location.segment_index || point.theta_rad !== location.theta_rad) {
    setStatus('定位与当前采样结果不一致，请重新计算。',true); return;
  }
  selectedEvidence = undefined; $('phase').value = location.sample_index;
  $('trace').value = trace; chart(); phase();
  $('profile').scrollIntoView({block:'center'});
}
function selectEvidence(witness) {
  selectLocation(witness.edge_a.start,$('trace').value);
  selectedEvidence = witness; phase();
}
function download(name,content,type='text/plain') {
  const url=URL.createObjectURL(new Blob([content],{type})); const a=document.createElement('a');a.href=url;a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
}
for (const b of document.querySelectorAll('[data-export]')) b.onclick=()=>{
 if(!latest||!latestInput)return;
 const ext=b.dataset.export;
 if(ext==='json'){download('mooncam.json',JSON.stringify({...latest,input:latestInput},null,2));return;}
 if(latest.result[ext]){download(`mooncam.${ext}`,latest.result[ext],ext==='svg'?'image/svg+xml':'text/plain');return;}
 dispatch({kind:'export',format:ext});
};
$('save-input').onclick=()=>{try{download('mooncam-input.json',JSON.stringify((latest&&latestInput)?latestInput:configuration('analyze'),null,2));}catch(e){setStatus(e.message,true);}};
$('analyze').onclick=()=>calculate('analyze');$('search').onclick=()=>calculate('search');$('phase').oninput=()=>{selectedEvidence=undefined;phase();};$('trace').onchange=chart;
let presetSequence = 0;
async function preset() {
  const token = ++presetSequence;
  revision++;
  try {
    const response=await fetch(`../examples/${$('preset').value}.json`); if(!response.ok)throw new Error('算例加载失败'); const p=await response.json(); if (token !== presetSequence) return;
    for(const [id,key] of Object.entries({base:'base_radius_mm',roller:'roller_radius_mm',offset:'offset_mm',rpm:'rpm',limit:'pressure_limit_deg',resolution:'resolution'}))$(id).value=p[key];
    editor.load(p.segments);
    $('search-options').open=p.action==='search';
    if(p.search)for(const [id,key]of Object.entries({lower:'lower_mm',upper:'upper_mm',intervals:'intervals'}))$(id).value=p.search[key];
  }catch(e){setStatus(e.message,true);}
}
$('preset').onchange=preset;
document.querySelector('.settings').addEventListener('input',()=>{revision++; if(latest)setStatus('参数已修改；当前图表和下载内容仍对应上次成功计算，请重新计算。');});
busy(true); await preset(); startWorker();
