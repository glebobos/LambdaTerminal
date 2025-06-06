#!/usr/bin/env bash
# Script to build and deploy the Lambda Terminal using SAM

set -e  # Exit on error

# Prepare JQ layer
./prepare-jq-layer.sh

# Check if SAM CLI is installed
if ! command -v sam &> /dev/null; then
    echo "SAM CLI is not installed. Please install it to proceed."
    exit 1
fi
# Build using SAM
echo "Building with SAM..."
sam build

# Optional deployment if --deploy flag is provided
if [ "$1" == "--deploy" ]; then
    echo "Deploying with SAM..."
    sam deploy
fi

echo "Build completed successfully!"
