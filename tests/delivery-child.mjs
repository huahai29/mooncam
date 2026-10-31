import {publishDirectory} from '../bin/delivery.mjs';
publishDirectory(process.argv[2],{'data.txt':'complete' },undefined,process.argv[3]==='pause'?{staged(){process.send('staged');Atomics.wait(new Int32Array(new SharedArrayBuffer(4)),0,0);}}:{});
