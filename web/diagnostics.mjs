// Display only. All positions, margins and verdicts are supplied by MoonBit.
const $ = id => document.getElementById(id);
const deg = rad => (rad * 180 / Math.PI).toFixed(2);
const number = value => Math.abs(value) < .001 && value !== 0 ? value.toExponential(3) : value.toFixed(4);
const states = {accepted_sampled:'采样通过', rejected:'采样拒绝', incomplete:'检查未完成'};
const reasons = {
  pressure_limit_exceeded:'压力角超过设定上限。可尝试增大基圆半径，再重新检查全部约束。',
  offset_factor_rejected:'局部偏置因子未严格大于阈值。请检查滚轮尺寸和运动段参数，再重新计算。',
  profile_crossings:'采样轮廓存在确定交叉，请查看下面的相关边。',
  geometry_indeterminate:'有边对的接触关系无法确定；当前结果未获接受，请查看相关范围。',
  geometry_failed:'轮廓检查失败，当前没有完整拓扑结论。',
  geometry_not_checked:'轮廓检查尚未执行，当前没有完整拓扑结论。',
};
function node(tag, text, className) {
  const e = document.createElement(tag);
  if (text !== undefined) e.textContent = text;
  if (className) e.className = className;
  return e;
}
function locationText(l) { return `第 ${l.segment_index+1} 段 · ${deg(l.theta_rad)}° · 点 ${l.sample_index}`; }
function edgeText(e) { return `边 ${e.edge_index}（第 ${e.segment_index+1} 段，${deg(e.start.theta_rad)}°—${deg(e.end.theta_rad)}°）`; }
export function renderDiagnostics(result, selectLocation, selectEvidence) {
  const root = $('diagnostics'); root.replaceChildren();
  for (const [key,title,trace] of [['pressure','压力角','pressure_deg'],['offset_factor','局部偏置因子','offset_factor']]) {
    const d = result.diagnostics[key], unit = key === 'pressure' ? '°' : '';
    const card = node('div',undefined,'diagnostic');
    card.append(node('strong',`${title}：${d.passed?'满足局部条件':'未满足局部条件'}`,d.passed?'good':'bad'));
    card.append(node('p',`最差值 ${number(d.value)}${unit}；阈值 ${number(d.limit)}${unit}；余量 ${number(d.margin)}${unit}。`));
    const button = node('button',`定位：${locationText(d.location)}`,'secondary');
    button.dataset.locate = key; button.dataset.sampleIndex = d.location.sample_index;
    button.onclick = () => selectLocation(d.location,trace); card.append(button); root.append(card);
  }
  const list = node('ul',undefined,'reason-list');
  for (const code of result.diagnostics.reasons) list.append(node('li',reasons[code] || `未识别诊断：${code}`));
  if (result.crossing_check.error) list.append(node('li',`检查信息：${result.crossing_check.error}`));
  root.append(list,node('p','余量只对应当前采样的局部约束；压力角允许等于上限，偏置因子必须严格大于阈值。段号从 1 展示，点号和边号从 0 编号。','hint'));
  const evidence = $('evidence'); evidence.replaceChildren(node('h3','交叉与不确定区域'));
  const data = result.crossing_evidence;
  for (const [i,w] of data.witnesses.entries()) {
    const label = w.kind === 'proper_crossing' ? '确定交叉' : w.kind === 'adjacent_reversal' ? '相邻边回折，待确认' : '接触关系不确定';
    const button = node('button',`${label}：${edgeText(w.edge_a)} 与 ${edgeText(w.edge_b)}`,'evidence-button secondary');
    button.dataset.witness = i; button.onclick = () => selectEvidence(w); evidence.append(button);
  }
  const empty = result.crossing_check.status === 'complete' ? '检查完成，未记录问题边对。' : '当前没有可展示的边对证据；请结合检查状态判断，不能据此视为零交叉。';
  evidence.append(node('p',data.witnesses.length ? `显示 ${data.witnesses.length} 组${data.truncated?'，其余已省略':''}；青色与紫色标出两条相关边，不表示精确交点。` : empty,'hint'));
  renderComparison(result.sampling_comparison);
}
function renderComparison(comparison) {
  $('comparison-panel').hidden = !comparison;
  const root = $('comparison'); root.replaceChildren();
  if (!comparison) return;
  const scroll = node('div',undefined,'table-scroll');
  const table = node('table'), head = node('tr'), thead = node('thead'), body = node('tbody');
  for (const text of ['分辨率 / 点数','最大压力角 / 余量','最小偏置因子 / 余量','最差压力角位置','最差偏置位置','综合 / 拓扑状态']) head.append(node('th',text));
  thead.append(head); table.append(thead);
  for (const level of comparison.levels) {
    const row = node('tr'), check = level.crossing_check;
    const topology = check.status === 'complete' ? `完成：${check.count} 交叉` : check.status === 'indeterminate' ? `不确定：${check.uncertain_pairs} 对` : '未完成';
    for (const text of [
      `${level.nominal_resolution} / ${level.sample_count}`,
      `${number(level.pressure.value)}° / ${number(level.pressure.margin)}°`,
      `${number(level.offset_factor.value)} / ${number(level.offset_factor.margin)}`,
      locationText(level.pressure.location), locationText(level.offset_factor.location),
      `${states[level.state]||level.state} / ${topology}`,
    ]) row.append(node('td',text));
    body.append(row);
  }
  table.append(body); scroll.append(table); root.append(scroll);
  root.append(node('p',`最后两档变化：最大压力角 ${number(comparison.last_pressure_change_deg)}°，最小偏置因子 ${number(comparison.last_offset_factor_change)}。${comparison.state_consistent?'各档综合状态相同。':'各档综合状态发生变化，请检查采样敏感性。'}`,comparison.state_consistent?'hint':'bad'));
  root.append(node('p','比较表中的点号只属于所在档位，不能直接定位到当前图。最差位置换段也可能来自对称或接近等高的峰值；请结合数值变化判断。数值稳定与状态一致均不构成连续轮廓证明。','hint'));
}
