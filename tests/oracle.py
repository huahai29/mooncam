"""Independent numerical geometry oracle. Standard Python only; not a runtime dependency."""
import json, math, subprocess
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]

def displacement(theta, law):
    t = theta % (2 * math.pi)
    section = int(t / (math.pi / 2))
    u = (t - section * math.pi / 2) / (math.pi / 2)
    if section in (1, 3):
        return 20.0 if section == 1 else 0.0
    if law == 'cycloidal':
        z = u - math.sin(2 * math.pi * u) / (2 * math.pi)
    else:
        # Smoothstep via Bernstein basis / binomial tail, not production's
        # expanded power polynomials or analytic derivative formulas.
        n = 5 if law == '345' else 7
        k0 = 3 if law == '345' else 4
        z = sum(math.comb(n,k) * u**k * (1-u)**(n-k) for k in range(k0,n+1))
    return 20*z if section == 0 else 20*(1-z)

def pitch(t, law, base, roller, offset):
    q = math.sqrt((base+roller)**2-offset**2) + displacement(t, law)
    return (q*math.sin(t)+offset*math.cos(t), q*math.cos(t)-offset*math.sin(t))

base_input = json.loads((ROOT/'examples/workshop.json').read_text())
cases=[]
for law in ['cycloidal','345','4567']:
    for offset in [-8,0,8]:
        for base in [25,40]:
            case = dict(base_input, base_radius_mm=base, offset_mm=offset, resolution=720)
            case['segments'] = [dict(s,law=law) for s in base_input['segments']]
            cases.append(case)
run = subprocess.run(['node',str(ROOT/'tests/engine-runner.mjs')],input='\n'.join(json.dumps(c) for c in cases),capture_output=True,text=True,check=True,cwd=ROOT)
checks=0
max_position_error=0.0
max_curvature_error=0.0
for case,line in zip(cases,run.stdout.splitlines(),strict=True):
    result=json.loads(line)
    assert result['ok'],result
    law=case['segments'][0]['law'];base=case['base_radius_mm'];offset=case['offset_mm'];roller=case['roller_radius_mm']
    for point in result['result']['points'][13:-1:29]:
        t=point['theta_rad']
        if min(t % (math.pi/2), math.pi/2-t % (math.pi/2))<0.01:continue
        h=0.0001
        p=pitch(t,law,base,roller,offset)
        l=pitch(t-h,law,base,roller,offset);r=pitch(t+h,law,base,roller,offset)
        dx=(r[0]-l[0])/(2*h);dy=(r[1]-l[1])/(2*h)
        ddx=(r[0]-2*p[0]+l[0])/h**2;ddy=(r[1]-2*p[1]+l[1])/h**2
        speed=math.hypot(dx,dy);nx=-dy/speed;ny=dx/speed
        curvature=(dy*ddx-dx*ddy)/speed**3
        expected=(p[0]-roller*nx,p[1]-roller*ny)
        error=math.hypot(point['x']-expected[0],point['y']-expected[1])
        max_position_error=max(max_position_error,error)
        max_curvature_error=max(max_curvature_error,abs(point['pitch_curvature']-curvature))
        assert error<0.00001,(case,t,error)
        assert abs(point['pitch_curvature']-curvature)<0.000001,(case,t,curvature)
        dot=nx*math.sin(t)+ny*math.cos(t)
        signed=-(nx*math.cos(t)-ny*math.sin(t))
        pressure=math.atan2(signed,dot)*180/math.pi
        assert abs(point['pressure_deg']-pressure)<0.0001
        checks+=1
summary={'cases':len(cases),'contact_points_checked':checks,'maximum_contact_error_mm':max_position_error,'maximum_curvature_error_per_mm':max_curvature_error}
print(json.dumps(summary,indent=2))
(ROOT/'artifacts').mkdir(exist_ok=True)
(ROOT/'artifacts/oracle-summary.json').write_text(json.dumps(summary,indent=2)+'\n')
