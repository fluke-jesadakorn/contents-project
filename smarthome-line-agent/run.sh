#!/bin/bash

# Navigate to the script's directory
cd "$(dirname "$0")"

# Load local .env variables into the environment safely
if [ -f .env ]; then
  echo "Loading environment variables from local .env..."
  set -a
  source .env
  set +a
else
  echo "⚠️  No .env file found in this directory. Falling back to ~/.hermes/.env values."
fi

# Run the Hermes gateway in the foreground
echo "🚀 Starting Nous Hermes Messaging Gateway..."
hermes gateway run
