import json, sys
from collections import Counter
rows=json.load(open(sys.argv[1]))
for s in ['A','B']:
    R=[r for r in rows if r['set']==s]; ok=[r for r in R if 'apple' in r]
    if not R: continue
    same=sum(r['apple']==r['claude'] for r in ok)
    add=lambda v,p,c: v=='dictionary' and p>=0.85 and c>=2
    ca=[r for r in ok if add(r['claude'],r['claudeP'],r['count'])]
    aa=[r for r in ok if add(r['apple'],r['appleP'],r['count'])]
    both=[r for r in aa if add(r['claude'],r['claudeP'],r['count'])]
    disagree=[r for r in aa if r['claude']!='dictionary']
    print(f"set {s}: {len(R)} items, {len(R)-len(ok)} errors, same verdict {same}/{len(ok)} = {100*same/max(1,len(ok)):.0f}%")
    print(f"  additions: claude {len(ca)}, apple {len(aa)}, both {len(both)}, apple where claude said otherwise {len(disagree)}")
    for r in disagree[:10]: print('    ', r['wrong'],'→',r['right'],'| claude',r['claude'],'| apple p',r['appleP'])
    print('  apple', Counter(r['apple'] for r in ok).most_common(), '\n  claude', Counter(r['claude'] for r in ok).most_common())
    dic=[r for r in ok if r['claude']=='dictionary']; print(f"  claude 'dictionary' also 'dictionary' for apple: {sum(r['apple']=='dictionary' for r in dic)}/{len(dic)}")
    errs=Counter(str(r.get('error'))[:70] for r in R if 'error' in r); print('  errors', errs.most_common(3))
    print(f"  time per item: {sum(r['seconds'] for r in R)/len(R):.1f} s")
