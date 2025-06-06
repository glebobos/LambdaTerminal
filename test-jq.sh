#!/usr/bin/env bash
# Test script to verify jq installation in Lambda

# Test if jq is properly downloaded and executable
echo "Testing jq ..."
echo '{"test":"success"}' | layers/jq/bin/jq .

# Display PATH
echo "Current PATH: $PATH"


