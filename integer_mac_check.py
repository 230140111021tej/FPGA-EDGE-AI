
import torch
import torch.nn as nn
from pathlib import Path
from torchvision import datasets, transforms

OUT = Path("outputs")
DEVICE = torch.device("cpu")

# Activation calibration maximum measured earlier.
INPUT_MAX = 6.421261310577393
INPUT_SCALE = INPUT_MAX / 255.0


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


# Use separate training images for calibration and evaluation.
dataset = datasets.MNIST(
    root="data",
    train=True,
    download=False,
    transform=transforms.ToTensor(),
)

calibration_images = torch.stack([
    dataset[i][0] for i in range(512)
])

images = torch.stack([
    dataset[i][0] for i in range(512, 640)
])

# Calibrate the actual input to the first fully connected layer.
with torch.no_grad():
    calibration_features = model.features(calibration_images)
    calibration_x = calibration_features.flatten(start_dim=1)

    x_float = model.features(images).flatten(start_dim=1)

    float_layer = model.classifier[1]
    reference = float_layer(x_float)

# All values here are nonnegative because of ReLU before pooling.
activation_max = calibration_x.max().item()
INPUT_SCALE = activation_max / 255.0

print("Calibrated FC input maximum:", activation_max)
print("Calibrated activation scale:", INPUT_SCALE)


# Quantize activations to unsigned INT8 levels: 0..255.
x_int = torch.round(
    x_float / INPUT_SCALE
).clamp(0, 255).to(torch.int64)

# Quantize weights symmetrically to signed INT8.
weight = float_layer.weight.detach()
weight_scale = weight.abs().max().item() / 127.0

w_int = torch.round(
    weight / weight_scale
).clamp(-127, 127).to(torch.int64)

# Bias uses the product scale of activation and weight.
bias = float_layer.bias.detach()
bias_scale = INPUT_SCALE * weight_scale

bias_int = torch.round(
    bias / bias_scale
).to(torch.int64)

# Integer dot product: unsigned activation x signed weight.
# INT64 is used in this Python reference to avoid overflow
# during the check; we separately verify INT32 limits.
acc = x_int @ w_int.T
acc = acc + bias_int

int32_min = -(2**31)
int32_max = 2**31 - 1

acc_min = acc.min().item()
acc_max = acc.max().item()

assert acc_min >= int32_min and acc_max <= int32_max, (
    "Accumulator exceeds signed INT32 range"
)

# Convert the integer accumulator back to real units.
integer_output = acc.float() * bias_scale

error = integer_output - reference

print("\n=== INTEGER MAC CHECK ===")
print("Input tensor shape:", tuple(x_float.shape))
print("Weight tensor shape:", tuple(weight.shape))
print("Activation scale:", INPUT_SCALE)
print("Weight scale:", weight_scale)
print("Accumulator scale:", bias_scale)
print("Accumulator minimum:", acc_min)
print("Accumulator maximum:", acc_max)
print("Accumulator fits INT32: YES")
print("Maximum absolute output error:", error.abs().max().item())
print("Mean absolute output error:", error.abs().mean().item())
print("RMSE:", error.square().mean().sqrt().item())

# Save reproducible summary.
import json

summary = {
    "input_shape": list(x_float.shape),
    "weight_shape": list(weight.shape),
    "activation_scale": INPUT_SCALE,
    "weight_scale": weight_scale,
    "accumulator_scale": bias_scale,
    "accumulator_min": acc_min,
"activation_calibration_samples": 512,
"activation_calibration_max": activation_max,
    "accumulator_max": acc_max,
    "accumulator_fits_int32": True,
    "max_absolute_output_error": error.abs().max().item(),
    "mean_absolute_output_error": error.abs().mean().item(),
    "rmse": error.square().mean().sqrt().item(),
    "sample_count": len(images),
}

with open(OUT / "integer_mac_results.json", "w") as f:
    json.dump(summary, f, indent=2)

print("Saved: outputs/integer_mac_results.json")
