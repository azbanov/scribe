#!/bin/bash

# Load environment variables from .env file
echo "Loading environment variables from .env..."
export $(grep -v '^#' .env | grep -v '^$' | xargs)

# Start Phoenix server
echo "Starting Phoenix server..."
iex -S mix phx.server
