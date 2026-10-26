// Documentation rendering only. Limits, states and exit mappings come from MoonBit.
import {readFileSync,writeFileSync} from 'node:fs';
import {contract} from '../web/engine.js';
const check=process.argv.includes('--check');
const root=new URL('../',import.meta.url);
const spec=JSON.parse(contract());
const descriptions={
 invalid_json:['JSON 语法无法解析','修正 JSON 语法'],
 invalid_input:['字段类型、取值或组合不符合输入约束；导出格式非法','根据 field 定位；整体约束错误可能为 null'],
 input_too_large:['请求超过 UTF-8 字节上限','减小请求；CLI 使用相同上限'],
 calculation_failed:['输入校验后发生导数溢出等数值失败；或搜索拓扑检查失败','调整输入并检查数值范围；不等于没有解'],
 check_indeterminate:['搜索遇到相切、重叠或符号不可靠的候选','调整几何或采样；不等于网格搜索无候选'],
 no_candidate:['访问完整有限网格后，没有通过复核的候选','扩大/细化网格；不证明连续空间无解'],
 internal_error:['未预期的计算异常','保存输入并报告问题'],
 no_result:['会话尚无成功结果，或上次计算失败后缓存已清空','先成功执行 Session::run；仅会话导出返回'],
};
const crossingMeaning={
 not_checked:['NotChecked','尚未执行拓扑检查；不会通过'],
 complete:['Checked(n)','检查完成，无不确定项；count 是严格交叉边对数'],
 indeterminate:['Indeterminate(n, k)','检查完成但含 k 个不确定边对；n 是已确定交叉数'],
 failed:['Failed(message)','非法点数组、数值范围或工作预算使检查失败'],
};
const limitLabels={
 resolution_min:'所有采样入口的名义分辨率下限',library_resolution_max:'MoonBit sample / measure / analyze 上限',
 json_resolution_max:'JSON analyze 的分辨率上限',search_resolution_max:'库与 JSON search 的粗网格上限',
 search_refinement:'搜索细网格分辨率倍数',segments_max:'程序段数上限',search_intervals_max:'基圆搜索区间数上限（位置数为区间数加一）',
 profile_points_min:'拓扑与 checked_export 的闭合点数组最小长度',profile_points_max:'拓扑与 checked_export 的闭合点数组最大长度',
 crossing_pair_budget:'桶内线段对访问预算（含被排除的候选对）',input_bytes_max:'JSON / CLI 输入 UTF-8 字节上限',
 base_radius_min:'基圆半径下限（JSON 单位 mm）',geometry_length_max:'基圆/滚轮半径与 JSON 单段升程绝对值上限',
 coordinate_max:'拓扑坐标、checked_export 数值的绝对值上限',segment_angle_min:'单段角度下限（rad）',
 closure_relative_tolerance:'首尾距离除以轮廓最大轴跨度的容差',
 offset_factor_min:'最小局部偏置因子必须严格大于此阈值',
 crossing_witnesses_max:'单次拓扑检查最多保留的边对证据数，不限制实际计数',
 comparison_levels_max:'MoonBit compare_sampling 允许的最多采样档位数',
};
for(const error of spec.errors)if(!descriptions[error.code])throw new Error(`Missing error documentation: ${error.code}`);
for(const state of spec.crossing_states)if(!crossingMeaning[state])throw new Error(`Missing state documentation: ${state}`);
for(const key of Object.keys(spec.limits))if(!limitLabels[key])throw new Error(`Missing limit documentation: ${key}`);
const table=(heads,rows)=>[heads,heads.map(()=>'---'),...rows].map(row=>'| '+row.join(' | ')+' |').join('\n');
const limits=table(['定义','当前值','含义'],Object.entries(spec.limits).sort(([a],[b])=>a.localeCompare(b)).map(([key,value])=>['`'+key+'`','`'+value+'`',limitLabels[key]]));
const errors=table(['error_code','CLI 退出码','含义','处理建议'],spec.errors.map(e=>['`'+e.code+'`',e.exit_code,...descriptions[e.code]]));
const states=table(['JSON status','MoonBit 状态','含义'],spec.crossing_states.map(s=>['`'+s+'`','`'+crossingMeaning[s][0]+'`',crossingMeaning[s][1]]));
const outcomes=table(['result.state','CLI 退出码'],spec.result_states.map(s=>['`'+s.state+'`',s.exit_code]));
for (const name of ['position_contract','diagnostic_contract']) {
 if (!spec[name]?.fields || !Object.keys(spec[name].fields).length) throw new Error(`Missing ${name}`);
 for (const [field,description] of Object.entries(spec[name].fields)) {
  if (typeof description !== 'string' || description.trim().length < 8) throw new Error(`Missing field description: ${name}.${field}`);
 }
}
const positionFields=table(['位置字段','含义'],Object.entries(spec.position_contract.fields).map(([field,description])=>['`'+field+'`',description]));
const diagnosticFields=table(['诊断与比较字段','含义'],Object.entries(spec.diagnostic_contract.fields).map(([field,description])=>['`'+field+'`',description]));
const markdown=`# 接口契约与错误码

<!-- 由 npm run docs:contract 生成；数值、状态和错误码源于 contract.mbt。 -->

当前 JSON schema 版本为 **${spec.schema_version}**，与项目包版本是不同概念。本轮保持 schema 2，增加状态与定位信息；调用方必须将未知状态视为未通过，不能默认当作零交叉。

## 生成版本

JSON 响应和报告的 generator 包含 name（MoonCam）、version（引擎包版本）及 source_digest（计算源码 SHA-256 指纹）。网页从实际加载的 MoonBit 引擎读取，CLI 保存时保留。schema_version 描述报告格式，与程序版本不同。

指纹覆盖生产 MoonBit 核心、桥接与模块配置，统一换行后计算；不包含测试、文档和网页宿主，不代表 Git 提交或整个网站的身份。同一版本下不同的计算源码使用不同指纹；下载的历史报告不会因网页更新而改变。构建前校验已提交的 version.mbt，修改引擎后执行 node scripts/version.mjs --write 并提交更新。

## 上限与单位

${limits}

不同入口的分辨率上限有意不同：库支持较大离线计算，JSON 控制响应成本，搜索还需双倍细网格复核。它们来自同一份 MoonBit 定义，搜索上限由 JSON 上限与复核倍数推导。库长度单位须一致，JSON 固定毫米。

分辨率是名义密度；每段向上取整并保留段界，实际点数由 sampling.sample_count 给出。profile_points 的限制指实际数组长度，含重复闭合点。闭合校验只依赖局部跨度；输入先转为 Double，已经丢失的细节无法恢复。

## 拓扑状态

${states}

仅 complete 提供整数 count。其余状态 count=null；indeterminate 额外提供 confirmed_crossings=n 和 uncertain_pairs=k。计数对应线段对，不能当作不同物理接触位置的数量。不确定状态不声称已精确区分相切、重叠和近退化。

## 综合结果与退出码

${outcomes}

accepted_sampled 当且仅当 sampled_local_feasible=true 且 crossing_check 为 complete/count=0。rejected 表示拓扑检查已完成，但局部约束或交叉数拒绝。incomplete 表示拓扑尚无完整确定结论；sampled_feasible=false 此时表示未获接受，不能直接解释为物理不可行。

ok=true 只表示获得了分析报告，可能仍是 rejected 或 incomplete。analyze 的 failed 拓扑保存在成功报告中，CLI 返回 4；search 中同类失败会中止搜索并返回 calculation_failed，CLI 返回 1。search 的几何不确定使用 check_indeterminate，退出 4。两种路径都不会降为零交叉或 no_candidate。

## 统一位置与采样编号

内部及 JSON 编号从 ${spec.position_contract.index_base} 开始，网页只对展示段号加一。段区间左闭右开；段界归右侧段。2π 闭合点保留最后一个 sample_index 和 theta_rad=2π，但周期运动归首段（segment_index=${spec.position_contract.periodic_endpoint_segment}）。最后一条边的归属为末段，而该边终点的位置归首段。

edge i 连接 points[i] 与 points[i+1]；含闭合点的 N+1 个点对应 N 条边。点号与边号仅在同一次采样结果内有效；跨分辨率只能结合段号和角度比较，不能比较下标。角度查询不自动选择最近采样点。

${positionFields}

points[] 增加 sample_index、segment_index，保留原有 theta_rad。result.segments 提供各段的 segment_index、start_rad、end_rad、law。locate_angle / locate_sample / locate_edge 与 evaluate 共用同一段查询；最差指标的下标在扫描时直接记录，严格更差才替换，等值时保留首个采样点。

## 诊断、余量与边对证据

${diagnosticFields}

约束诊断还包含 code、value、limit、passed、unit 与 location。MoonBit 压力角及余量为弧度，JSON 统一换成度（unit=deg）；偏置因子无量纲。reasons 的稳定原因码为：${spec.diagnostic_contract.reason_codes.map(s=>'`'+s+'`').join('、')}。它们不替代原有综合状态与退出码。

witness.kind 允许：${spec.diagnostic_contract.witness_kinds.map(s=>'`'+s+'`').join('、')}。proper_crossing 为确定交叉；其余是未获精确分类的可疑边对。edge_a 与 edge_b 各自含 edge_index、边归属 segment_index、start/end 位置以及 start_x、start_y、end_x、end_y，坐标固定毫米。证据在 outputs=[] 时仍保留，失败检查不提供部分证据；是否通过始终依据 crossing_check 与局部约束。边对数量不等于独立交点数量。

compare_sampling=true 时以最终报告的名义分辨率 r 取三档：若 4r 不超过 JSON 上限，使用 [r,2r,4r]；否则使用 [floor(r/4),floor(r/2),r]。搜索比较的是最终候选尺寸，其 r 为复核分辨率，不重新搜索三个尺寸。当前档复用，其余执行完整分析；请求没有开启时不额外计算。

各档包含 nominal_resolution、sample_count、pressure、offset_factor、crossing_check、state。比较只展示观测变化，不输出“已收敛”或安全认证；某档失败或不确定仍原样记录，数值计算错误则整个请求失败并清空会话。state_consistent 只比较综合状态，拓扑细节仍须逐档查看。

## 错误码汇总

${errors}

错误响应含 ok=false、schema_version、error_code、error 与 field。error 是面向人的说明，调用方不得解析或比较其文本。field 是字段路径，例如 segments[0].law、search.intervals；缺少明确单一字段时为 null。未知错误码的宿主退出码为 1，未知结果状态同样返回 1。

主机文件打开、权限、UTF-8 解码和写出失败由 CLI 捕获并返回 1，不伪装成 MoonBit 数值错误。CLI 批量的既有严重度顺序见[输入输出说明](输入输出说明.md)。

## 文档生成与兼容

执行 moon info、npm run build、npm run docs:contract 更新本页、机器可读的[接口契约 JSON](接口契约.json)与[公共 API](公共API.md)的签名段。npm run docs:check 校验它们与当前 MoonBit 产物一致，CI 会执行同一检查。

公共类型的字段与枚举见根目录 pkg.generated.mbti。接口快照有意提交；web/engine.js、_build、artifacts 是构建或验证产物，不提交。
`;
function sorted(value){if(Array.isArray(value))return value.map(sorted);if(value&&typeof value==='object')return Object.fromEntries(Object.keys(value).sort().map(key=>[key,sorted(value[key])]));return value;}
const snapshot=readFileSync(new URL('pkg.generated.mbti',root),'utf8').replace(/\r\n/g,'\n');
const signatures=snapshot.split('\n').filter(line=>line.startsWith('pub fn ')).join('\n');
const apiPath=new URL('docs/公共API.md',root),api=readFileSync(apiPath,'utf8').replace(/\r\n/g,'\n');
const begin='<!-- BEGIN GENERATED API -->',end='<!-- END GENERATED API -->';
if(!api.includes(begin)||!api.includes(end))throw new Error('Missing API signature markers');
const generated=api.slice(0,api.indexOf(begin))+begin+'\n\n```moonbit\n'+signatures+'\n```\n\n'+api.slice(api.indexOf(end));
for(const[path,content]of [['docs/接口契约.md',markdown],['docs/接口契约.json',JSON.stringify(sorted(spec),null,2)+'\n'],['docs/公共API.md',generated]]){
 const url=new URL(path,root);
 if(check){let old;try{old=readFileSync(url,'utf8').replace(/\r\n/g,'\n');}catch{}if(old!==content){console.error(`Stale contract document: ${path}; run npm run docs:contract`);process.exitCode=1;}}
 else{writeFileSync(url,content,'utf8');console.log(`Updated ${path}`);}
}
