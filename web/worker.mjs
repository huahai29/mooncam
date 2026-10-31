import * as engine from './engine.js';
import {executeTask} from './engine-task.mjs';
self.postMessage({ready: true, contract: JSON.parse(engine.contract())});
self.onmessage = ({data}) => {
  try { self.postMessage({id:data.id,response:executeTask(engine,data)}); }
  catch (error) { self.postMessage({id:data.id,error:error.message}); }
};
