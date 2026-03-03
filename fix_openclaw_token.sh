#!/bin/bash

# Define the path to the configuration file
CONFIG_FILE="/root/.openclaw/openclaw.json"

# Backup the original configuration file
cp "$CONFIG_FILE" "$CONFIG_FILE.bak"

echo "Backup of openclaw.json created at $CONFIG_FILE.bak"

# Update the gateway token in the JSON file
jq '.gateway.auth.token = "matching-gateway-auth-token"' "$CONFIG_FILE" > tmp.$$.json && mv tmp.$$.json "$CONFIG_FILE"

echo "Gateway token updated successfully."
