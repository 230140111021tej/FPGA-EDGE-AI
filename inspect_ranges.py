
import json
from pathlib import Path

import torch
import torch.nn as nn
from torchvision import datasets, transforms

DEVICE = torch.device("cpu")
OUT = Path("outputs")
OUT.mkdir(exist_ok=True)


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


model = SmallCNN().to(DEVICE)
model.load_state_dict(
    torch.load(
        OUT / "best_mnist_cnn.pth",
        map_location=DEVICE,
        weights_only=True,
    )
)
model.eval()

# Use training data for activation calibration.
dataset = datasets.MNIST(
    root="data",
    train=True,
    download=False,
    transform=transforms.ToTensor(),
)
calibration_images = torch.stack(
    [dataset[i][0] for i in range(512)]
)

records = {}
handles = []


def make_hook(name):
    def hook(module, inputs, output):
        values = output.detach().float()
        records[name] = {
            "output_min": values.min().item(),
            "output_max": values.max().item(),
            "output_abs_max": values.abs().max().item(),
        }
    return hook


for name, layer in model.named_modules():
    if isinstance(layer, (nn.Conv2d, nn.Linear, nn.ReLU)):
        handles.append(
            layer.register_forward_hook(make_hook(name))
        )

with torch.no_grad():
    model(calibration_images)

for handle in handles:
    handle.remove()

print("\n=== WEIGHT AND ACTIVATION RANGES ===")

for name, layer in model.named_modules():
    if isinstance(layer, (nn.Conv2d, nn.Linear)):
        weights = layer.weight.detach().float()
        info = records.get(name, {})

        info.update({
            "layer_type": type(layer).__name__,
            "weight_shape": list(weights.shape),
            "weight_min": weights.min().item(),
            "weight_max": weights.max().item(),
            "weight_abs_max": weights.abs().max().item(),
            "weight_abs_p99": torch.quantile(
                weights.abs().flatten(), 0.99
            ).item(),
            "bias_abs_max": (
                layer.bias.detach().abs().max().item()
                if layer.bias is not None else 0.0
            ),
        })

        records[name] = info

        print(f"\n{name} ({info['layer_type']})")
        for key, value in info.items():
            if key != "layer_type":
                print(f"  {key}: {value}")

with open(OUT / "ranges.json", "w") as f:
    json.dump(records, f, indent=2)

print("\nSaved: outputs/ranges.json")
