#!/bin/bash

# Load environment variables from .env file
# Get the absolute path to the project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_ROOT/.env"

if [ -f "$ENV_FILE" ]; then
    export $(cat "$ENV_FILE" | grep -v '^#' | xargs)
else
    echo "ERROR: .env file not found at $ENV_FILE"
    echo "Please run bootstrap-chaos-environment.sh first"
    exit 1
fi

# Validate critical variables are set
REQUIRED_VARS=(
    "SOLACE_BROKER_HOST"
    "SOLACE_BROKER_PORT"
    "SDKPERF_SCRIPT_PATH"
    "CHAOS_GENERATOR_USER"
    "CHAOS_GENERATOR_PASSWORD"
)

for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        echo "ERROR: Required environment variable $var is not set"
        exit 1
    fi
done
