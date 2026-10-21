"""Read generated scientific-notation coordinates with an independent DXF library."""
import io,json,math,subprocess,sys
from pathlib import Path
import ezdxf
ROOT=Path(__file__).resolve().parents[1]
base=json.loads((ROOT/'examples/workshop.json').read_text())
cases=[base,dict(base,offset_mm=10)]
small=dict(base,base_radius_mm=0.00004,roller_radius_mm=0.000004,offset_mm=0)
small['segments']=[dict(s,lift_mm=s['lift_mm']*0.000001) for s in base['segments']]
cases.append(small)
node=subprocess.run(['node',str(ROOT/'tests/engine-runner.mjs')],input='\n'.join(json.dumps(dict(c,outputs=['points','dxf'])) for c in cases),text=True,capture_output=True,check=True,cwd=ROOT)
scientific=0
for line in node.stdout.splitlines():
 response=json.loads(line);assert response['ok'],response
 r=response['result'];doc=ezdxf.read(io.StringIO(r['dxf']))
 polylines=list(doc.modelspace().query('LWPOLYLINE'));assert len(polylines)==1
 poly=polylines[0];assert poly.closed;assert doc.header['$INSUNITS']==4
 coords=list(poly.get_points('xy'));assert len(coords)==len(r['points'])-1
 for xy,p in zip(coords,r['points'][:-1],strict=True):
  assert math.isclose(xy[0],p['x'],rel_tol=1e-12,abs_tol=1e-15)
  assert math.isclose(xy[1],p['y'],rel_tol=1e-12,abs_tol=1e-15)
 tags=r['dxf'].strip().split('\n')
 for i in range(0,len(tags),2):
  if tags[i] in ('10','20') and 'e' in tags[i+1].lower():scientific+=1
assert scientific>0
summary={'reader':'ezdxf '+ezdxf.__version__,'cases':len(cases),'scientific_coordinate_values_read':scientific,'result':'accepted by this reader; not a claim about every CAD application'}
print(json.dumps(summary,indent=2))
(ROOT/'artifacts').mkdir(exist_ok=True)
(ROOT/'artifacts/dxf-interop.json').write_text(json.dumps(summary,indent=2)+'\n')
