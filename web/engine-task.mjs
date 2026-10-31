// Host routing only. Every profile string still comes from the same MoonBit Session.
export function executeTask(engine,task){
 if(task.kind==='bundle'){
  const files={};
  for(const format of ['csv','svg','dxf']){
   const response=JSON.parse(engine.export_profile(format));
   if(!response.ok)return response;
   files[format]=response.content;
  }
  return {ok:true,files};
 }
 return JSON.parse(task.kind==='validate'?engine.validate_segments(task.input):task.kind==='export'?engine.export_profile(task.format):engine.run(task.input));
}
