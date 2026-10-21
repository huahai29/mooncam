import { run } from './engine.js';
self.postMessage({ready: true});
self.onmessage = event => {
  try { self.postMessage({response: JSON.parse(run(event.data))}); }
  catch (error) { self.postMessage({error: error.message}); }
};
