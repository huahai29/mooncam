// DOM editing only. MoonBit validates the serialized array and computes totals.
const laws = [['4567','4-5-6-7'],['345','3-4-5'],['cycloidal','摆线']];
export function segmentEditor(validate, changed) {
  const body = document.getElementById('segment-rows');
  const draft = document.getElementById('segments');
  const summary = document.getElementById('segment-summary');
  const add = document.getElementById('add-segment');
  let token = 0, timer, max = 128;
  function values() {
    return [...body.rows].map(row => Object.fromEntries(['angle_deg','lift_mm','law'].map(key => {
      const value = row.querySelector(`[data-field="${key}"]`).value;
      return [key,key === 'law' ? value : value.trim() === '' ? null : Number(value)];
    })));
  }
  function show(result) {
    for (const el of body.querySelectorAll('[aria-invalid]')) el.removeAttribute('aria-invalid');
    for (const el of body.querySelectorAll('.segment-error')) el.remove();
    const totals = result.total_angle_deg === undefined ? '' : `总转角 ${Number(result.total_angle_deg.toFixed(6))}° / 360°；总升程 ${Number(result.total_lift_mm.toFixed(6))} mm / 0 mm。`;
    summary.textContent = totals + (result.ok ? '分段程序通过校验。' : '分段程序未通过，请调整后再计算。');
    summary.className = result.ok ? 'hint good' : 'hint bad';
    if (!result.ok) {
      const match = /^segments\[(\d+)\]\.(angle_deg|lift_mm|law)$/.exec(result.field || '');
      const label = match ? {angle_deg:'转角须为有效正数，并满足最小段角度。',lift_mm:'升程须为有效数值，且累计升程不得为负、单段幅度不得超限。',law:'请选择支持的运动规律。'}[match[2]] : '请检查段数、总转角为 360°、最终升程回零，以及 JSON 字段。';
      const error = document.createElement('p'); error.className = 'segment-error bad'; error.textContent = label;
      const input = match && body.rows[Number(match[1])]?.querySelector(`[data-field="${match[2]}"]`);
      if (input) {input.setAttribute('aria-invalid','true'); input.parentElement.append(error);}
      else summary.append(error);
    }
  }
  function check() {
    const request = ++token; clearTimeout(timer);
    draft.value = JSON.stringify(values(),null,2);
    summary.textContent = '等待 MoonBit 校验…';
    timer = setTimeout(() => validate(draft.value, result => {if(request === token)show(result);}),150);
  }
  function renumber() {
    [...body.rows].forEach((row,i) => {
      row.cells[0].textContent = String(i+1);
      for (const input of row.querySelectorAll('[data-field]')) input.setAttribute('aria-label', `第 ${i+1} 段${{angle_deg:'转角',lift_mm:'升程',law:'运动规律'}[input.dataset.field]}`);
      row.querySelector('button').setAttribute('aria-label',`删除第 ${i+1} 段`);
    });
    add.disabled = body.rows.length >= max;
  }
  function append(segment) {
    const row = body.insertRow(); row.insertCell();
    for (const key of ['angle_deg','lift_mm','law']) {
      const input = document.createElement(key === 'law' ? 'select' : 'input'); input.dataset.field = key;
      if (key === 'law') for (const [value,label] of laws) {const option=document.createElement('option');option.value=value;option.textContent=label;input.append(option);}
      else {input.type='number';input.step='any';}
      input.value = segment[key] ?? ''; row.insertCell().append(input);
    }
    const remove = document.createElement('button'); remove.type='button';remove.className='secondary';remove.textContent='删除';
    remove.onclick=()=>{row.remove();renumber();check();changed();};row.insertCell().append(remove);
  }
  body.addEventListener('input',check);
  add.onclick=()=>{if(body.rows.length>=max)return;append({angle_deg:90,lift_mm:0,law:'4567'});renumber();check();changed();};
  function load(segments) {body.replaceChildren();for(const s of segments)append(s);renumber();check();}
  document.getElementById('apply-segments').onclick=()=>{
    const input=draft.value, request=++token;clearTimeout(timer);
    validate(input,result=>{
      if(request!==token)return;
      const status=document.getElementById('import-status');
      if(!result.ok){status.textContent=`导入失败：${result.field || '分段数组'}，请检查 JSON 语法、字段和闭合条件。当前表格保留。`;return;}
      load(JSON.parse(input));changed();status.textContent='已导入表格，各段运动规律已保留。';
    });
  };
  draft.addEventListener('input',()=>{++token;clearTimeout(timer);document.getElementById('import-status').textContent='文本尚未导入；计算使用当前表格。';});
  return {values,load,check,setLimit(n){max=n;renumber();}};
}
