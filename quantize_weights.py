
import copy
import json
from pathlib import Path

import torch
import torch.nn as nn
from torchvision import datasets, transforms
from torch.utils.data import DataLoader

DEVICE = torch.device("cpu")
OUT = Path("outputs")
OUT.mkdir(exist_ok=True)

BATCH_SIZE = 256


class SmallCNN(nn.Module):
    def __init__(self):
        super().__init__()
        self.features = nn.Sequential(
            nn.Conv2d(1, 16, 3, padding=1),
            nn.ReLU(),
            nn.MaxPool2d(2),
            nn.Conv2d(16, 32, 3, padding=1),
            nn.ReLU(),
            nn.MaxPool2d(2),
        )
        self.classifier = nn.Sequential(
            nn.Flatten(),
            nn.Linear(32 * 7 * 7, 64),
            nn.ReLU(),
            nn.Linear(64, 10),
        )

    def forward(self, x):
        return self.classifier(self.features(x))


def load_model():
    model = SmallCNN().to(DEVICE)
    state = torch.load(
        OUT / "best_mnist_cnn.pth",
        map_location=DEVICE,
        weights_only=True,
    )
    model.load_state_dict(state)
    return model.eval()


def evaluate(model, loader):
    model.eval()
    correct = 0
    total = 0

    with torch.no_grad():
        for images, labels in loader:
            logits = model(images.to(DEVICE))
            correct += (
                logits.argmax(dim=1) == labels.to(DEVICE)
            ).sum().item()
            total += len(labels)

    return 100.0 * correct / total


# Load the untouched floating-point baseline.
baseline = load_model()
quantized_model = copy.deepcopy(baseline)

test_dataset = datasets.MNIST(
    root="data",
    train=False,
    download=False,
    transform=transforms.ToTensor(),
)

test_loader = DataLoader(
    test_dataset,
    batch_size=BATCH_SIZE,
    shuffle=False,
    num_workers=0,
)

baseline_accuracy = evaluate(baseline, test_loader)

# Symmetric signed INT8 quantization, independently per layer.
integer_weights = {}
scales = {}
weight_errors = {}

for name, layer in quantized_model.named_modules():
    if not isinstance(layer, (nn.Conv2d, nn.Linear)):
        continue

    original = layer.weight.detach().clone()

    # Symmetric scale: map max absolute weight to 127.
    scale = original.abs().max().item() / 127.0
    if scale == 0:
        scale = 1.0

    q = torch.round(original / scale).clamp(-127, 127)
    q = q.to(torch.int8)

    # Dequantize to floating point to test weight-rounding effects.
    reconstructed = q.float() * scale
    layer.weight.data.copy_(reconstructed)

    integer_weights[name] = q.cpu()
    scales[name] = scale

    error = reconstructed - original
    weight_errors[name] = {
        "max_abs_error": error.abs().max().item(),
        "mean_abs_error": error.abs().mean().item(),
        "scale": scale,
        "weight_count": original.numel(),
    }

quantized_model.eval()
quantized_accuracy = evaluate(quantized_model, test_loader)

# Compare predictions on the complete test set.
changed_predictions = 0
total_samples = 0

with torch.no_grad():
    for images, _ in test_loader:
        images = images.to(DEVICE)

        p_float = baseline(images).argmax(dim=1)
        p_quant = quantized_model(images).argmax(dim=1)

        changed_predictions += (
            p_float != p_quant
        ).sum().item()
        total_samples += len(images)

torch.save(
    integer_weights,
    OUT / "weights_int8.pt",
)

with open(OUT / "weight_scales.json", "w") as f:
    json.dump(scales, f, indent=2)

results = {
    "method": "per-layer symmetric INT8 weights; float activations",
    "baseline_test_accuracy_percent": baseline_accuracy,
    "quantized_weight_test_accuracy_percent": quantized_accuracy,
    "accuracy_change_percentage_points": (
        quantized_accuracy - baseline_accuracy
    ),
    "changed_predictions_vs_baseline": changed_predictions,
    "test_samples": total_samples,
    "layers": weight_errors,
    "integer_weights_file": "outputs/weights_int8.pt",
    "scales_file": "outputs/weight_scales.json",
}

with open(OUT / "weight_quantization_results.json", "w") as f:
    json.dump(results, f, indent=2)

print("\n=== WEIGHT-ONLY INT8 RESULTS ===")
print(f"Baseline test accuracy: {baseline_accuracy:.2f}%")
print(f"INT8-weight test accuracy: {quantized_accuracy:.2f}%")
print(
    "Accuracy change: "
    f"{quantized_accuracy - baseline_accuracy:+.2f} percentage points"
)
print(
    f"Changed predictions: {changed_predictions}/{total_samples}"
)

for name, stats in weight_errors.items():
    print(
        f"{name}: scale={stats['scale']:.8g}, "
        f"max_weight_error={stats['max_abs_error']:.8g}"
    )

print("\nSaved: outputs/weights_int8.pt")
print("Saved: outputs/weight_scales.json")
print("Saved: outputs/weight_quantization_results.json")
