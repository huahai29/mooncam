// Independent ZIP reader for tests: verifies central records, local headers and Node's CRC.
import assert from 'node:assert/strict';
import {crc32} from 'node:zlib';
export function readZip(bytes){
 const b=Buffer.from(bytes),end=b.length-22;
 assert.equal(b.readUInt32LE(end),0x06054b50);
 const count=b.readUInt16LE(end+10),directory=b.readUInt32LE(end+16),size=b.readUInt32LE(end+12);
 assert.equal(directory+size,end);
 const files={};let cursor=directory;
 for(let i=0;i<count;i++){
  assert.equal(b.readUInt32LE(cursor),0x02014b50);
  assert.equal(b.readUInt16LE(cursor+10),0);
  const n=b.readUInt16LE(cursor+28),length=b.readUInt32LE(cursor+24),offset=b.readUInt32LE(cursor+42),crc=b.readUInt32LE(cursor+16);
  const name=b.subarray(cursor+46,cursor+46+n).toString('utf8');
  assert.equal(b.readUInt32LE(offset),0x04034b50);
  assert.equal(b.readUInt16LE(offset+8),0);
  assert.equal(b.readUInt32LE(offset+18),length);
  const localName=b.readUInt16LE(offset+26),extra=b.readUInt16LE(offset+28);
  assert.equal(b.subarray(offset+30,offset+30+localName).toString('utf8'),name);
  const data=b.subarray(offset+30+localName+extra,offset+30+localName+extra+length);
  assert.equal(crc32(data),crc);assert.equal(crc,b.readUInt32LE(offset+14));
  assert.equal(files[name],undefined);files[name]=data.toString('utf8');
  cursor+=46+n+b.readUInt16LE(cursor+30)+b.readUInt16LE(cursor+32);
 }
 assert.equal(cursor,end);assert.equal(Object.keys(files).length,count);
 return files;
}
