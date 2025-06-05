#!/bin/bash

CONFIG_FILE="./vmconfig.conf"

if [[ -f "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
else
  echo "[!] Missing config file: $CONFIG_FILE"
  exit 1
fi

VM_NAME="$1"

if [[ -z "$VM_NAME" ]]; then
  echo "Usage: $0 <vm-name>"
  exit 1
fi

VMX_PATH="${VM_OUTPUT_DIR}/${VM_NAME}/${VM_NAME}.vmx"

if [[ ! -f "$VMX_PATH" ]]; then
  echo "[!] VMX file not found: $VMX_PATH"
  exit 1
fi

# Windows-style path for vmrun
WIN_VMX=$(wslpath -w "$VMX_PATH")

# Fetch IP (non-blocking, fast-fail)
IP=$("$VMRUN" -T ws getGuestIPAddress "$WIN_VMX" 2>/dev/null | tr -d '\r')

ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "$USERNAME@$IP"
