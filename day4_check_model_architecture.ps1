$ErrorActionPreference = "Stop"
$root = "D:\FPGA_EdgeAI\cnn_baseline"
Set-Location $root

$py = @'
from pathlib import Path
import ast, json

root = Path(r"D:\FPGA_EdgeAI\cnn_baseline")
out = root / "outputs" / "rtl_params" / "architecture_sources.txt"
terms = ("class SmallCNN", "class MNIST", "Conv2d(", "MaxPool2d(", "AdaptiveAvgPool", "classifier", "features", "padding=")
roots = [root / "scripts", root / "experiments", root / "models", root]
found = []
seen = set()
for base in roots:
    if not base.exists():
        continue
    for p in base.rglob("*.py"):
        if p in seen or any(part in {".git", "data", "venv", ".venv", "site-packages"} for part in p.parts):
            continue
        seen.add(p)
        try:
            text = p.read_text(errors="ignore")
        except Exception:
            continue
        hits = [(i, line.rstrip()) for i, line in enumerate(text.splitlines(), 1)
                if any(term in line for term in terms)]
        if hits:
            found.append((p, hits))

lines = []
lines.append("CNN MODEL ARCHITECTURE SOURCE SEARCH")
lines.append(f"Project root: {root}")
lines.append("")
for p, hits in found:
    lines.append(f"=== {p} ===")
    source = p.read_text(errors="ignore").splitlines()
    # Print surrounding context around the most relevant model/layer declarations.
    selected = set()
    for i, line in hits:
        for n in range(max(1, i-2), min(len(source), i+3)+1):
            selected.add(n)
    for n in sorted(selected):
        lines.append(f"{n}: {source[n-1]}")
    lines.append("")

manifest = root / "outputs" / "rtl_params" / "manifest.json"
if manifest.exists():
    data = json.loads(manifest.read_text())
    lines.append("=== SHAPE CHECK ===")
    lines.append(f"FC1 weight shape: {data['layers']['classifier.1']['weight_shape']}")
    lines.append("FC1 input features: 1568")
    lines.append("32 channels x 7 x 7 spatial = 1568")
    lines.append("Current valid Conv1 spatial size: 26 x 26")
    lines.append("If Conv1 and Conv2 are both valid and each followed by 2x2 pooling: final spatial size = 5 x 5; flatten = 800")

out.parent.mkdir(parents=True, exist_ok=True)
out.write_text("\n".join(lines), encoding="utf-8")
print("\n".join(lines[:450]))
print(f"\nFull report saved to: {out}")
'@
Set-Content "scripts\inspect_cnn_architecture.py" $py -Encoding ascii
python scripts\inspect_cnn_architecture.py
if ($LASTEXITCODE -ne 0) { throw "Architecture source inspection failed." }
