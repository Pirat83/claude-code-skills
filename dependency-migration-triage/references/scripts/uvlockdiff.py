# usage: python3 -I uvlockdiff.py <repo> <revA> <revB>   (needs Python >= 3.11 for tomllib)
# prints one line per package whose version set changed: "name: old -> new" ("-" = absent)
# tested 2026-11-01 on unternehmen-walkuere (quantstats, redis changed; ipython dropped)
import subprocess, sys, tomllib
repo, a, b = sys.argv[1:4]
def load(rev):
    raw = subprocess.run(["git", "-C", repo, "show", f"{rev}:uv.lock"], check=True, capture_output=True).stdout
    d = {}
    for p in tomllib.loads(raw.decode())["package"]:
        d.setdefault(p["name"], set()).add(p.get("version", "(" + p["source"].get("virtual", p["source"].get("editable", "?")) + ")"))
    return d
old, new = load(a), load(b)
for n in sorted(old.keys() | new.keys()):
    o, w = old.get(n, set()), new.get(n, set())
    if o != w:
        print(f"{n}: {', '.join(sorted(o)) or '-'} -> {', '.join(sorted(w)) or '-'}")
