#!/bin/bash

set -e

CONFIG_FILE="./vmconfig.conf"

if [[ -f "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
else
  echo "[!] Missing config file: $CONFIG_FILE"
  echo "    Run ./setup.sh to create it."
  exit 1
fi

# === Default options ===
OS_TYPE="ubuntu-24"

# === OS -> Image Map ===
declare -A IMAGE_URLS=(
  [ubuntu-24]="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  [ubuntu-22]="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
)

print_usage() {
  echo "Usage: $0 --os <template> <vm-name>"
  echo "       $0 --list-os"
  exit 1
}

if [[ "$1" == "--list-os" ]]; then
  echo "Available OS templates:"
  for os in "${!IMAGE_URLS[@]}"; do
    echo "  - $os"
  done
  exit 0
fi

# === Parse flags ===
OS_TYPE=""
VM_NAME=""

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --os)
      OS_TYPE="$2"
      shift 2
      ;;
    -*)
      echo "[!] Unknown option: $1"
      print_usage
      ;;
    *)
      VM_NAME="$1"
      shift
      ;;
  esac
done

if [[ -z "$OS_TYPE" || -z "$VM_NAME" ]]; then
  echo "[!] Missing required arguments."
  print_usage
fi

TEMPLATE_DIR="./templates/${OS_TYPE}"
TEMPLATE_VMDK="${TEMPLATE_DIR}/${OS_TYPE}.vmdk"
TEMPLATE_VMX="${TEMPLATE_DIR}/${OS_TYPE}.vmx"

if [[ ! -f "$TEMPLATE_VMDK" ]]; then
  echo "[*] VMDK for $OS_TYPE not found. Attempting to download and convert."
  TEMP_IMG="/tmp/${OS_TYPE}.img"
  URL="${IMAGE_URLS[$OS_TYPE]}"
  if [[ -z "$URL" ]]; then
    echo "[!] No image URL known for OS: $OS_TYPE"
    exit 1
  fi
  mkdir -p "$TEMPLATE_DIR"
  wget -O "$TEMP_IMG" "$URL"
  echo "[*] Converting to VMDK..."
  qemu-img convert -p -f qcow2 -O vmdk "$TEMP_IMG" "$TEMPLATE_VMDK"
  rm "$TEMP_IMG"
fi

if [[ ! -f "$TEMPLATE_VMX" ]]; then
  echo "[!] Missing ${OS_TYPE}.vmx in $TEMPLATE_DIR"
  exit 1
fi

# === Init paths ===
SSH_KEY=$(cat "$SSH_KEY_PATH")
UUID=$(uuidgen)
VM_DIR="${VM_OUTPUT_DIR}/${VM_NAME}"

# Abort if VM already exists
if [[ -e "$VM_DIR" ]]; then
  echo "[!] VM '${VM_NAME}' already exists at $VM_DIR"
  exit 1
fi

SEED_DIR="${VM_DIR}/seed"
SEED_ISO="${VM_DIR}/seed.iso"
VMX="${VM_DIR}/${VM_NAME}.vmx"

echo "[*] Creating VM directory..."
mkdir -p "$SEED_DIR"
cp "$TEMPLATE_DIR/"* "$VM_DIR/"

echo "[*] Generating meta-data and user-data..."
cat > "${SEED_DIR}/meta-data" <<EOF
instance-id: iid-${UUID}
local-hostname: ${VM_NAME}
dsmode: local
EOF

cat > "${SEED_DIR}/user-data" <<EOF
#cloud-config
users:
  - name: ${USERNAME}
    groups: sudo
    sudo: ALL=(ALL) NOPASSWD:ALL
    chpasswd: { expire: False }
    hashed_passwd: "$6$xiFV/vdLomMezlAI$7sTlj8E6vdXziOI7AGUpiCofGHaf8z/fJDTsHTs2ptdfQCIJW.bHhAoS7Q/bUHeeDij1EVREZ54hbHa/bdiOG."
    shell: /bin/bash
    ssh_authorized_keys:
      - ${SSH_KEY}
ssh_pwauth: false
disable_root: false
packages:
  - open-vm-tools

runcmd:
  - systemctl enable --now open-vm-tools
  - rm -f /etc/machine-id
  - rm -f /var/lib/dbus/machine-id
  - systemd-machine-id-setup
  - rm -f /var/lib/dhcp/*
  - systemctl restart systemd-networkd

final_message: "Cloud-init finished at \$epoch seconds"
EOF

echo "[*] Creating seed.iso..."
genisoimage -output "$SEED_ISO" -volid cidata -joliet -rock \
  "${SEED_DIR}/user-data" "${SEED_DIR}/meta-data"

NEW_DISK_NAME="${VM_NAME}.vmdk"
NEW_VMX_NAME="${VM_NAME}.vmx"

mv "$VM_DIR/${OS_TYPE}.vmdk" "$VM_DIR/${NEW_DISK_NAME}"
mv "$VM_DIR/${OS_TYPE}.vmx" "$VM_DIR/${NEW_VMX_NAME}"

echo "[*] Updating VMX file..."
sed -i "s/^ide1:0.fileName = .*/ide1:0.fileName = \"$(basename "$SEED_ISO")\"/" "$VM_DIR/${NEW_VMX_NAME}"
sed -i "s/^displayName = .*/displayName = \"${VM_NAME}\"/" "$VM_DIR/${NEW_VMX_NAME}"
sed -i "s|^scsi0:0.fileName = .*|scsi0:0.fileName = \"${NEW_DISK_NAME}\"|" "$VM_DIR/${NEW_VMX_NAME}"
sed -i "s|^nvram = .*|nvram = \"${VM_NAME}.nvram\"|" "$VM_DIR/${NEW_VMX_NAME}"

echo "[*] Booting VM..."
WIN_VMX=$(wslpath -w "$VM_DIR/${NEW_VMX_NAME}")
"$VMRUN" start "$WIN_VMX" nogui

echo "[+] Done. VM '${VM_NAME}' started."

echo "[*] Attempting to fetch IP..."
"$VMRUN" -T ws getGuestIPAddress "$WIN_VMX" -wait
