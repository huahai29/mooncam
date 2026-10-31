// A ZIP container is a browser file-save concern; no model or export algorithm lives here.
const utf8=new TextEncoder();
function crc32(bytes){
 let crc=0xffffffff;
 for(const byte of bytes){crc^=byte;for(let bit=0;bit<8;bit++)crc=(crc>>>1)^((crc&1)?0xedb88320:0);}
 return (crc^0xffffffff)>>>0;
}
export function zipFiles(files){
 const parts=[],directory=[];let offset=0;
 const names=new Set();
 for(const [name,text] of Object.entries(files)){
  if(!/^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(name)||names.has(name))throw Error('无效的归档文件名');
  names.add(name);
  const filename=utf8.encode(name),data=utf8.encode(text),crc=crc32(data);
  if(filename.length>65535)throw Error('归档文件名过长');
  const local=new Uint8Array(30+filename.length),v=new DataView(local.buffer);
  v.setUint32(0,0x04034b50,true);v.setUint16(4,20,true);v.setUint16(6,0x0800,true);
  v.setUint16(12,33,true);v.setUint32(14,crc,true);v.setUint32(18,data.length,true);v.setUint32(22,data.length,true);v.setUint16(26,filename.length,true);local.set(filename,30);
  const central=new Uint8Array(46+filename.length),c=new DataView(central.buffer);
  c.setUint32(0,0x02014b50,true);c.setUint16(4,20,true);c.setUint16(6,20,true);c.setUint16(8,0x0800,true);
  c.setUint16(14,33,true);c.setUint32(16,crc,true);c.setUint32(20,data.length,true);c.setUint32(24,data.length,true);c.setUint16(28,filename.length,true);c.setUint32(42,offset,true);central.set(filename,46);
  parts.push(local,data);directory.push(central);offset+=local.length+data.length;
  if(offset>0xffffffff)throw Error('结果包超过 ZIP 容量上限');
 }
 if(!names.size||names.size>65535)throw Error('归档文件数量无效');
 const size=directory.reduce((n,part)=>n+part.length,0),end=new Uint8Array(22),e=new DataView(end.buffer);
 e.setUint32(0,0x06054b50,true);e.setUint16(8,names.size,true);e.setUint16(10,names.size,true);e.setUint32(12,size,true);e.setUint32(16,offset,true);
 return new Blob([...parts,...directory,end],{type:'application/zip'});
}
export function resultBundle(snapshot,exports){
 const {response,request}=snapshot,r=response.result;
 if(!response.ok||!r||!request)throw Error('没有可保存的计算结果');
 for(const format of ['csv','svg','dxf'])if(typeof exports[format]!=='string'||!exports[format])throw Error(`缺少 ${format} 导出`);
 const {search,...configuration}=request;
 const input={...configuration,action:'analyze',base_radius_mm:r.base_radius_mm,resolution:r.sampling.nominal_resolution};
 const {points,csv,svg,dxf,...summary}=r;
 const references={input:'input.json',request:'request.json',csv:'profile.csv',svg:'profile.svg',dxf:'profile.dxf'};
 const report={...response,result:summary,input:request,files:references};
 const generator=response.generator||r.generator;
 if(!generator?.version||!generator.source_digest)throw Error('结果缺少引擎版本信息');
 const text=value=>JSON.stringify(value,null,2)+'\n';
 const state={accepted_sampled:'采样检查通过',rejected:'采样检查拒绝',incomplete:'检查未完成'}[r.state]||r.state;
 const readme=`# MoonCam 本次计算结果

- 结论：${state}；以 report.json 中的状态与诊断为准。
- 基圆半径：${r.base_radius_mm} mm；滚轮半径：${r.roller_radius_mm} mm；偏置：${r.offset_mm} mm。
- 转速：${request.rpm} rpm；压力角限制：${request.pressure_limit_deg}°。
- 最大绝对压力角：${r.max_pressure_deg}°；压力角余量：${r.diagnostics.pressure.margin}°。
- 名义分辨率：${r.sampling.nominal_resolution}；实际采样点：${r.sample_count}。
- 引擎：MoonCam ${generator.version}；JSON schema：${response.schema_version}。
- 源码指纹：${generator.source_digest}。

## 文件与复算

- input.json：最终尺寸的分析配置；搜索结果使用复核分辨率，可直接复算同一尺寸。
- request.json：提交计算时的原始配置，保留搜索范围等信息。
- report.json：原始分析或搜索报告的摘要，input 字段对应 request.json；点表及图形通过 files 引用，不重复内嵌。
- profile.csv：逐点分析数据；profile.svg：轮廓预览；profile.dxf：毫米制闭合轮廓。
- manifest.json：文件清单、结果状态和生成版本。

在 MoonCam 仓库构建后，执行：

\`\`\`sh
node bin/mooncam.mjs input.json --out artifacts/recheck
\`\`\`

如需重跑原始搜索或分析，改用 request.json。使用相同版本、源码指纹和参数便于核对结果；不同工具链的浮点结果可能有微小差异。

这些文件对应上次成功计算时的输入，不包含随后尚未计算的编辑。采样通过不是连续安全证明，能导出或被 CAD 打开也不代表可以直接加工。拒绝或未完成的结果仍可保存用于排查。
`;
 const files={'input.json':text(input),'request.json':text(request),'report.json':text(report),'profile.csv':exports.csv,'profile.svg':exports.svg,'profile.dxf':exports.dxf,'README.md':readme};
 files['manifest.json']=text({bundle_schema:'mooncam.result-bundle.v1',generator,schema_version:response.schema_version,source_action:request.action,state:r.state,files:[...Object.keys(files),'manifest.json']});
 return zipFiles(files);
}
