#!/usr/bin/env bash
# Script to download jq and prepare the layer

# Create directory structure if it doesn't exist
mkdir -p layers/jq/bin

# Download jq binary
echo "Downloading jq..."
curl -L https://github.com/jqlang/jq/releases/download/jq-1.8.0/jq-linux64 -o layers/jq/bin/jq

# Make jq executable
chmod +x layers/jq/bin/jq

echo "JQ layer prepared successfully!"
