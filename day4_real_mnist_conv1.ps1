$ErrorActionPreference = "Stop"
$root = "D:\FPGA_EdgeAI\cnn_baseline"
Set-Location $root

$exporter = @'
from pathlib import Path
import sys

root = Path(r"D:\FPGA_EdgeAI\cnn_baseline")
rom = root / "rom"
rom.mkdir(parents=True, exist_ok=True)
image_path = rom / "conv1_image_u8_hex.mem"
backup_path = rom / "conv1_image_u8_placeholder_backup.mem"

try:
    from torchvision.datasets import MNIST
except Exception as e:
    raise SystemExit(
        "Could not import torchvision MNIST. Install compatible torch/torchvision first.\n"
        f"Details: {e}"
    )

# Download occurs only if the MNIST dataset is not already cached.
try:
    ds = MNIST(root=str(root / "data"), train=False, download=True)
except Exception as e:
    raise SystemExit(
        "Could not load/download MNIST. Check network access or place the MNIST dataset "
        f"in the local data directory.\nDetails: {e}"
    )

# Find a clear, deterministic example: first test-set image with label 7.
selected = next((i for i in range(len(ds)) if int(ds[i][1]) == 7), 0)
img, label = ds[selected]
pixels = list(img.convert("L").getdata())
if len(pixels) != 784:
    raise SystemExit(f"Expected 784 pixels, got {len(pixels)}")

# Preserve the previous image ROM once, so the placeholder can be restored later.
if image_path.exists() and not backup_path.exists():
    backup_path.write_text(image_path.read_text())

image_path.write_text("".join(f"{v:02X}\n" for v in pixels))
(root / "rom" / "conv1_image_info.txt").write_text(
    f"dataset=MNIST test\nindex={selected}\nlabel={label}\npixels=784\n"
    "encoding=28x28 grayscale uint8, row-major, 00-FF\n"
)
print(f"Exported real MNIST image: index={selected}, label={label}, pixels={len(pixels)}")
print(f"Updated ROM: {image_path}")
print(f"Previous ROM backup: {backup_path if backup_path.exists() else 'not created (no prior ROM existed)'}")
'@
Set-Content "scripts\export_real_mnist_image.py" $exporter -Encoding ascii

python scripts\export_real_mnist_image.py
if ($LASTEXITCODE -ne 0) { throw "MNIST image export failed; simulation was not run." }

$verify = Join-Path $root "day3_add_requant_validation_fixed.ps1"
if (-not (Test-Path $verify)) {
    throw "Missing day3_add_requant_validation_fixed.ps1. Save the previously supplied fixed validation script in $root first."
}
& powershell -ExecutionPolicy Bypass -File $verify
if ($LASTEXITCODE -ne 0) { throw "Conv1 RTL/Python validation failed." }

Write-Host ""
Write-Host "REAL MNIST CONV1 VALIDATION COMPLETE"
Write-Host "Image metadata: rom\conv1_image_info.txt"
Write-Host "RTL accumulators: conv1_rtl_outputs.txt"
Write-Host "RTL activations: conv1_rtl_activations.txt"
