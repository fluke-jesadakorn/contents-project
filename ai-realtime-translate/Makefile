.PHONY: all build bundle sign run clean install-deps help

# Default target: build, bundle, and ad-hoc sign the app
all: build bundle sign

# Compile release binary
build:
	@echo "🔨 Building release binary..."
	cargo build --release

# Bundle the macOS app
bundle:
	@echo "📦 Bundling macOS app..."
	dx bundle --package-types macos

# Sign the app with ad-hoc signature to preserve permissions
sign:
	@echo "✍️ Signing application with ad-hoc signature..."
	codesign --force --deep --sign - target/dx/foundry/bundle/macos/macos/Foundry.app

# Run the bundled app
run: all
	@echo "🚀 Launching Foundry..."
	open target/dx/foundry/bundle/macos/macos/Foundry.app

# Clean build artifacts
clean:
	@echo "🧹 Cleaning cargo artifacts..."
	cargo clean

# Install all development dependencies (Homebrew + Python venv)
install-deps:
	@echo "📦 Installing whisper-cpp via Homebrew..."
	brew install whisper-cpp || true
	@echo "🐍 Creating Python virtual environment..."
	python3 -m venv .venv
	@echo "pip upgrading..."
	.venv/bin/pip install --upgrade pip
	@echo "Installing python packages..."
	.venv/bin/pip install mlx-lm mlx-whisper numpy
	@echo "📂 Downloading default whisper-tiny model..."
	mkdir -p ~/whisper-models
	curl -L https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin -o ~/whisper-models/ggml-tiny.bin

# Help menu
help:
	@echo "Foundry Desktop Makefile Targets:"
	@echo "  make              - Build, bundle, and sign the application (default)"
	@echo "  make build        - Compile Cargo release build"
	@echo "  make bundle       - Run Dioxus bundle packager"
	@echo "  make sign         - Apply ad-hoc signature (fixes permissions popups)"
	@echo "  make run          - Build, bundle, sign, and launch the application"
	@echo "  make install-deps - Install Homebrew tools + Python MLX virtual environment"
	@echo "  make clean        - Remove cargo build artifacts"
