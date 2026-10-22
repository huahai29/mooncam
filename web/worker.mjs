import { run, export_profile, contract } from './engine.js';
self.postMessage({ready: true, contract: JSON.parse(contract())});
self.onmessage = ({data}) => {
  try {
    const response = JSON.parse(data.kind === 'export' ? export_profile(data.format) : run(data.input));
    self.postMessage({id: data.id, response});
  } catch (error) { self.postMessage({id: data.id, error: error.message}); }
};
