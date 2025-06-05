#!/bin/bash

CONFIG_FILE="./vmconfig.conf"
VMS_OUTPUT_FILE="./vms.csv"

if [[ -f "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
else
  echo "[!] Missing config file: $CONFIG_FILE"
  exit 1
fi

echo "Hostname,IP" > $VMS_OUTPUT_FILE

echo "[*] Running VMs with IPs:"

IFS=$'\r\n' GLOBIGNORE='*' command eval 'vm_list=($("$VMRUN" list | tail -n +2))'

for win_path in "${vm_list[@]}"; do
    unix_path=$(echo "$win_path" | sed 's|\\|/|g')
    vm_file=$(basename "$unix_path")
    vm_name="${vm_file%.vmx}"
    ip=$("$VMRUN" -T ws getGuestIPAddress "$win_path" 2>/dev/null || echo "Unavailable")
    echo "- $vm_name - $ip"
    echo "$vm_name,$ip" >> $VMS_OUTPUT_FILE
done

echo ""
echo "[*] All VMs:"
find "$VM_OUTPUT_DIR" -name '*.vmx' | sed 's#.*/##' | sed 's/\.vmx$//'
