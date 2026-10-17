
import copy
import json
from pathlib import Path

import torch
import torch.nn as nn
from torch.utils.data import DataLoader
from torchvision import datasets, transforms

DEVICE = torch.device("cpu")
OUT = Path("outputs")
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
        # Quantize the input image to unsigned 8-bit levels.
        x = fake_quant_unsigned(x, 1.0)

        x = self.features[0](x)
        x = self.features[1](x)
        x = self.features[2](x)
        x = fake_quant_unsigned(x, 2.1746950149536133)

        x = self.features[3](x)
        x = self.features[4](x)
        x = self.features[5](x)
        x = fake_quant_unsigned(x, 6.421261310577393)

        x = self.classifier[0](x)
        x = self.classifier[1](x)
        x = self.classifier[2](x)
        x = fake_quant_unsigned(x, 27.94095802307129)

        x = self.classifier[3](x)
        return x


def fake_quant_unsigned(x, max_value):
    # Simulate unsigned 8-bit quantization with zero point 0.
    scale = max_value / 255.0
    q = torch.round(x / scale).clamp(0, 255)
    return q * scale


def load_model():
    model = SmallCNN().to(DEVICE)
    model.load_state_dict(
        torch.load(
            OUT / "best_mnist_cnn.pth",
            map_location=DEVICE,
            weights_only=True,
        )
    )
    return model


def quantize_weights_per_layer(model):
    scales = {}

    for name, layer in model.named_modules():
        if isinstance(layer, (nn.Conv2d, nn.Linear)):
            w = layer.weight.detach()
            scale = w.abs().max().item() / 127.0
            if scale == 0:
                scale = 1.0

            q = torch.round(w / scale).clamp(-127, 127)
            layer.weight.data.copy_(q * scale)
            scales[name] = scale

    return scales


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


# Test set is used only for final evaluation.
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

# Baseline uses original floating-point weights and activations.
baseline = load_model()
baseline_accuracy = evaluate(baseline, test_loader)

# Candidate uses INT8-rounded weights and fake-quantized activations.
candidate = load_model()
weight_scales = quantize_weights_per_layer(candidate)
candidate.eval()
quantized_accuracy = evaluate(candidate, test_loader)

results = {
    "method": (
        "per-layer INT8 weight rounding and unsigned "
        "8-bit fake quantization of activations"
    ),
    "baseline_test_accuracy_percent": baseline_accuracy,
    "quantized_test_accuracy_percent": quantized_accuracy,
    "accuracy_change_percentage_points": (
        quantized_accuracy - baseline_accuracy
    ),
    "activation_max_values": {
        "input": 1.0,
        "after_pool1": 2.1746950149536133,
        "after_pool2": 6.421261310577393,
        "after_relu_fc1": 27.94095802307129,
    },
    "weight_scales": weight_scales,
    "test_samples": len(test_dataset),
}

with open(OUT / "activation_quantization_results.json", "w") as f:
    json.dump(results, f, indent=2)

print("\n=== WEIGHT + ACTIVATION QUANTIZATION ===")
print(f"Baseline accuracy: {baseline_accuracy:.2f}%")
print(f"Quantized accuracy: {quantized_accuracy:.2f}%")
print(
    "Accuracy change: "
    f"{quantized_accuracy - baseline_accuracy:+.2f} percentage points"
)
print("Saved: outputs/activation_quantization_results.json")
