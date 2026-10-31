"""Two fixed-case accuracy experiments, not an error certificate for arbitrary input."""
import json,math,subprocess,os,sys
from pathlib import Path
from fractions import Fraction as F
from decimal import Decimal as D
from importlib.util import spec_from_file_location,module_from_spec
ROOT=Path(__file__).resolve().parents[1]
spec=spec_from_file_location('highprec',ROOT/'tests/oracle_highprec.py');hp=module_from_spec(spec);spec.loader.exec_module(hp)
def trim(p):
 while len(p)>1 and p[-1]==0:p.pop()
 return p
def add(a,b):return trim([(a[i] if i<len(a) else 0)+(b[i] if i<len(b) else 0) for i in range(max(len(a),len(b)))])
def scale(p,k):return trim([x*k for x in p])
def mul(a,b):
 r=[F(0)]*(len(a)+len(b)-1)
 for i,x in enumerate(a):
  for j,y in enumerate(b):r[i+j]+=x*y
 return trim(r)
def derivative(p):return [p[i]*i for i in range(1,len(p))] or [F(0)]
def value(p,x):
 r=0
 for a in reversed(p):r=r*x+a
 return r
def divide(a,b):
 a=a[:];q=[F(0)]*max(1,len(a)-len(b)+1)
 while len(a)>=len(b) and a!=[0]:
  n=len(a)-len(b);v=a[-1]/b[-1];q[n]=v
  a=add(a,scale([F(0)]*n+b,-v))
 return trim(q),trim(a)
def roots_between_endpoints(p):
 for x in [F(0),F(1)]:
  while value(p,x)==0:p,rem=divide(p,[-x,F(1)]);assert rem==[0]
 seq=[p,derivative(p)]
 while seq[-1]!=[0]:
  _,rem=divide(seq[-2],seq[-1])
  if rem==[0]:break
  seq.append(scale(rem,-1))
 def changes(x):
  signs=[1 if value(p,x)>0 else -1 for p in seq if value(p,x)!=0]
  return sum(a!=b for a,b in zip(signs,signs[1:]))
 return changes(F(0))-changes(F(1))
def reference(analytic):
 f=list(map(F,[0,0,0,10,-15,6] if analytic else [0,0,0,0,35,-84,70,-20]))
 v=derivative(f);a=derivative(v);q=F(20)*F(2568,16807) if analytic else F(44)
 stationary=add(scale(mul(a,add([q],scale(f,20))),20),scale(mul(v,v),-400))
 assert roots_between_endpoints(stationary)==1
 if analytic:
  u=D(2)/7;assert value(stationary,F(2,7))==0
 else:
  lo,hi=D('0.4'),D('0.5')
  coefficients=[D(x.numerator)/D(x.denominator) for x in stationary]
  for _ in range(120):
   mid=(lo+hi)/2
   if value(coefficients,mid)>0:lo=mid
   else:hi=mid
  u=(lo+hi)/2
 conv=lambda p:[D(x.numerator)/D(x.denominator) for x in p]
 qd=D(q.numerator)/D(q.denominator)
 angle=hp.dec_atan(20*value(conv(v),u)/(hp.PI/2)/(qd+20*value(conv(f),u)))*180/hp.PI
 return float(angle),float(90*u),str(angle)
def main():
 subprocess.run([os.environ.get('MOON','moon'),'build','--target','js','--release'],cwd=ROOT,check=True)
 output=subprocess.check_output(['node','tests/sampling-runner.mjs'],cwd=ROOT,text=True)
 rows=json.loads(output.strip().splitlines()[-1]);refs={}
 for analytic in [False,True]:
  name='analytic345' if analytic else 'workshop';ref,position,precise=reference(analytic);refs[name]={'maximum_deg':precise,'rise_position_deg':position,'critical_roots_per_rise':1}
  group=[r for r in rows if r['case']==name]
  for i,r in enumerate(group):
   r['reference_deg']=ref;r['error_deg']=ref-r['maximum']
   r['delta_to_next_deg']=abs(r['maximum']-group[i+1]['maximum']) if i<3 else None
   # Treat symmetric rise/return maxima as the same position family.
   r['position_error_deg']=min(abs(r['position']-position),abs(r['position']-(270-position)))
   assert -1e-10<=r['error_deg']<0.01
   if i:assert r['error_deg']<=group[i-1]['error_deg']+1e-10
  for i,r in enumerate(group):
   e=r['error_deg'];prev=group[i-1]['error_deg'] if i else 0
   r['observed_order']=math.log2(prev/e) if i and prev>1e-10 and e>1e-10 and prev-e>1e-10 else None
 assert rows[0]['delta_to_next_deg']==0 and rows[0]['error_deg']>1e-4
 report={'scope':'Fixed-case actual error against analytic/stationary reference; not a general certified bound. Exact rational Sturm counts isolate all interior rise critical points; decimal evaluation is a numerical approximation, not directed rounding.','references':refs,'rows':rows}
 out=ROOT/'artifacts/sampling';out.mkdir(parents=True,exist_ok=True)
 (out/'results.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
 expected=json.loads((ROOT/'docs/experiments/sampling-results.json').read_text()) if (ROOT/'docs/experiments/sampling-results.json').exists() else None
 if expected:
  assert len(rows)==len(expected['rows'])==8
  for r,e in zip(rows,expected['rows']):assert abs(r['maximum']-e['maximum'])<1e-8
 if '--record' in sys.argv:
  dest=ROOT/'docs/experiments';dest.mkdir(exist_ok=True);(dest/'sampling-results.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
  import matplotlib;matplotlib.use('Agg')
  import matplotlib.pyplot as plt
  fig,axes=plt.subplots(1,2,figsize=(10,4))
  for name in refs:
   g=[r for r in rows if r['case']==name]
   axes[0].loglog([r['n'] for r in g],[max(r['error_deg'],1e-15) for r in g],'o-',label=name)
   axes[1].plot([r['n'] for r in g[:-1]],[r['delta_to_next_deg'] for r in g[:-1]],'o-',label=name)
  axes[0].set(xlabel='Nominal resolution N',ylabel='Actual error against reference (deg)')
  axes[1].set(xlabel='Nominal resolution N',ylabel='|maximum(N) - maximum(2N)| (deg)')
  for ax in axes:ax.legend();ax.grid(True,alpha=.3)
  fig.tight_layout();fig.savefig(dest/'sampling.png',dpi=160);plt.close(fig)
 print(json.dumps(report,indent=2))
if __name__=='__main__':main()
