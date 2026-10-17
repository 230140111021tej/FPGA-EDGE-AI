
import json
from pathlib import Path

import torch
import torch.nn as nn
from torchvision import datasets, transforms

SEED = 42
torch.manual_seed(SEED)

DEVICE = torch.device("cpu")
OUT = Path("outputs")
OUT.mkdir(exist_ok=True)


class SmallCNN(nn.Module):
    def __init__(self):
        super().__init__()

        self.features = nn.Sequential(
            nn.Conv2d(1, 16, kernel_size=3, padding=1),
            nn.ReLU(),
            nn.MaxPool2d(2),
            nn.Conv2d(16, 32, kernel_size=3, padding=1),
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

# Count trainable parameters
total_params = sum(
    p.numel() for p in model.parameters()
)

print("\n=== PARAMETER COUNT ===")
print("Total parameters:", total_params)

for name, layer in model.named_children():
    count = sum(p.numel() for p in layer.parameters())
    print(f"{name}: {count} parameters")

# Print output shapes at each layer
print("\n=== LAYER OUTPUT SHAPES ===")
x = torch.zeros(1, 1, 28, 28)

with torch.no_grad():
    for name, layer in model.features.named_children():
        x = layer(x)
        print(f"features.{name}: {tuple(x.shape)}")

    for name, layer in model.classifier.named_children():
        x = layer(x)
        print(f"classifier.{name}: {tuple(x.shape)}")

# Load a small, fixed group of test images
test_dataset = datasets.MNIST(
    root="data",
    train=False,
    download=False,
    transform=transforms.ToTensor(),
)

images = torch.stack([
    test_dataset[i][0] for i in range(16)
]).to(DEVICE)

labels = torch.tensor([
    test_dataset[i][1] for i in range(16)
])

# Generate floating-point reference outputs
with torch.no_grad():
    logits = model(images)
    predictions = logits.argmax(dim=1)

correct = (predictions == labels).sum().item()

print("\n=== REFERENCE CHECK ===")
print("Reference images:", len(images))
print("Correct predictions:", correct, "/ 16")
print("First 10 predictions:", predictions[:10].tolist())
print("First 10 labels:", labels[:10].tolist())

# Save reference inputs and logits for future RTL comparison
torch.save(
    {
        "images": images,
        "labels": labels,
        "logits": logits,
        "predictions": predictions,
    },
    OUT / "golden_vectors.pt",
)

summary = {
    "seed": SEED,
    "total_parameters": total_params,
    "reference_image_count": len(images),
    "correct_reference_predictions": correct,
    "output_shape": list(logits.shape),
    "reference_file": "outputs/golden_vectors.pt",
}

with open(OUT / "architecture.json", "w") as f:
    json.dump(summary, f, indent=2)

print("\nSaved: outputs/golden_vectors.pt")
print("Saved: outputs/architecture.json")
