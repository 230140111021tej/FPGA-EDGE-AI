
import json
import random
import time
from pathlib import Path

import torch
import torch.nn as nn
from torch.utils.data import DataLoader, random_split
from torchvision import datasets, transforms

# Reproducible experiment
SEED = 42
random.seed(SEED)
torch.manual_seed(SEED)

DEVICE = torch.device("cpu")
BATCH_SIZE = 128
EPOCHS = 5
LEARNING_RATE = 0.001

OUT = Path("outputs")
OUT.mkdir(exist_ok=True)

print("PyTorch version:", torch.__version__)
print("Training device:", DEVICE)

# Download and prepare MNIST
transform = transforms.ToTensor()

full_train = datasets.MNIST(
    root="data", train=True, download=True, transform=transform
)
test_dataset = datasets.MNIST(
    root="data", train=False, download=True, transform=transform
)

train_dataset, val_dataset = random_split(
    full_train,
    [55000, 5000],
    generator=torch.Generator().manual_seed(SEED),
)

def make_loader(dataset, shuffle=False):
    return DataLoader(
        dataset,
        batch_size=BATCH_SIZE,
        shuffle=shuffle,
        num_workers=0,
        generator=torch.Generator().manual_seed(SEED),
    )

train_loader = make_loader(train_dataset, shuffle=True)
val_loader = make_loader(val_dataset)
test_loader = make_loader(test_dataset)

print("Training images:", len(train_dataset))
print("Validation images:", len(val_dataset))
print("Test images:", len(test_dataset))

# CNN model
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
        x = self.features(x)
        return self.classifier(x)

model = SmallCNN().to(DEVICE)
criterion = nn.CrossEntropyLoss()
optimizer = torch.optim.Adam(
    model.parameters(), lr=LEARNING_RATE
)

# Evaluate loss and accuracy
def evaluate(loader):
    model.eval()
    correct = 0
    total_loss = 0.0
    count = 0

    with torch.no_grad():
        for images, labels in loader:
            images = images.to(DEVICE)
            labels = labels.to(DEVICE)

            logits = model(images)
            loss = criterion(logits, labels)

            total_loss += loss.item() * len(labels)
            correct += (
                logits.argmax(dim=1) == labels
            ).sum().item()
            count += len(labels)

    return total_loss / count, 100.0 * correct / count

# Train the model
best_accuracy = -1.0
best_epoch = 0
history = []

for epoch in range(1, EPOCHS + 1):
    model.train()
    total_loss = 0.0

    for images, labels in train_loader:
        images = images.to(DEVICE)
        labels = labels.to(DEVICE)

        optimizer.zero_grad()
        logits = model(images)
        loss = criterion(logits, labels)
        loss.backward()
        optimizer.step()

        total_loss += loss.item() * len(labels)

    train_loss = total_loss / len(train_dataset)
    val_loss, val_accuracy = evaluate(val_loader)

    history.append({
        "epoch": epoch,
        "train_loss": train_loss,
        "val_loss": val_loss,
        "val_accuracy_percent": val_accuracy,
    })

    print(
        f"Epoch {epoch}/{EPOCHS} | "
        f"train_loss={train_loss:.4f} | "
        f"val_loss={val_loss:.4f} | "
        f"val_accuracy={val_accuracy:.2f}%"
    )

    if val_accuracy > best_accuracy:
        best_accuracy = val_accuracy
        best_epoch = epoch
        torch.save(
            model.state_dict(),
            OUT / "best_mnist_cnn.pth"
        )

# Load best model and evaluate test set
model.load_state_dict(
    torch.load(
        OUT / "best_mnist_cnn.pth",
        map_location=DEVICE,
        weights_only=True,
    )
)

test_loss, test_accuracy = evaluate(test_loader)

# Measure saved model size
model_path = OUT / "best_mnist_cnn.pth"
model_size_bytes = model_path.stat().st_size

# Measure single-image inference latency
model.eval()
sample = torch.zeros(1, 1, 28, 28)

with torch.no_grad():
    for _ in range(10):
        model(sample)

    iterations = 100
    start = time.perf_counter()

    for _ in range(iterations):
        model(sample)

    latency_ms = (
        (time.perf_counter() - start) * 1000 / iterations
    )

# Save all experiment results
results = {
    "seed": SEED,
    "device": str(DEVICE),
    "pytorch_version": torch.__version__,
    "train_samples": len(train_dataset),
    "validation_samples": len(val_dataset),
    "test_samples": len(test_dataset),
    "epochs": EPOCHS,
    "best_epoch": best_epoch,
    "best_validation_accuracy_percent": best_accuracy,
    "test_accuracy_percent": test_accuracy,
    "test_loss": test_loss,
    "model_size_bytes": model_size_bytes,
    "model_size_KiB": model_size_bytes / 1024,
    "inference_batch_size": 1,
    "average_inference_latency_ms": latency_ms,
    "training_history": history,
}

with open(OUT / "results.json", "w") as f:
    json.dump(results, f, indent=2)

print("\n========== FINAL RESULTS ==========")
print(f"Best epoch: {best_epoch}")
print(f"Test accuracy: {test_accuracy:.2f}%")
print(f"Test loss: {test_loss:.4f}")
print(f"Model size: {model_size_bytes / 1024:.2f} KiB")
print(f"Average inference latency: {latency_ms:.4f} ms")
print("Model saved to:", model_path)
print("Results saved to: outputs/results.json")
