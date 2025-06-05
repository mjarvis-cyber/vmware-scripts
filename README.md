# VMWare Workstation Scripts
This repo provides scripts which can be run from WSL to interact with VMWare Workstation on the host

## Getting Started
* Run `./setup.sh` to create the `./vmconfig.conf`
* If prompted, install the necessary tools to interact with VMs

## Creating a new VM
* Run `./create-vm.sh --list-os` to view available operating systems
* Run `./create-vm.sh --os <desired-os> <my-vm-name>` to create a VM 
