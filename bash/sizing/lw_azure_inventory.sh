#!/bin/bash
# Script to fetch Azure inventory for Lacework sizing.
# Requirements: az cli, jq, zsh or bash 4+

# This script can be run from Azure Cloud Shell.

# Set the initial counts to zero.

#TODO: future state, support a flag to filter on subscription or management group scope

AZURE_VMS_VCPU=0
AZURE_VMSS_VCPU=0
VM_SKU_vCPU_MAP=map

echo "Building SKU to vCPU map..."
VM_SKU_vCPU_MAP_LINES=$(az vm list-skus | jq -r '.[] | .name as $parent | select(.capabilities != null) | .capabilities[] | select(.name == "vCPUs") | $parent+":"+.value' | sort | uniq)
for line in $VM_SKU_vCPU_MAP_LINES;
  map line by splitting on colon
echo "Map built successfully."

# No need to iterate subscriptions when using Azure Resource Graph -- this will populate for all subscriptions the user has access to!

echo "Running Az Resource Graph Query for VMs"
echo "az graph query -q 'Resources | where type=~\'microsoft.compute/virtualmachines\' | project subscriptionId, name, sku=properties.hardwareProfile.vmSize'"
vms=$(az graph query -q "Resources | where type=~'microsoft.compute/virtualmachines' | project subscriptionId, name, sku=properties.hardwareProfile.vmSize")

echo $vms

echo "Running Az Resource Graph Query for VMSS"
echo "az graph query -q 'Resources | where type=~ \'microsoft.compute/virtualmachinescalesets\' | project subscriptionId, name, sku=sku.name, capacity = toint(sku.capacity)"
vmss=$(az graph query -q "Resources | where type=~ 'microsoft.compute/virtualmachinescalesets' | project subscriptionId, name, sku=sku.name, capacity = toint(sku.capacity)")

echo $vmss

for vm in $vms:
  AZURE_VMS_VCPU+=VM_SKU_vCPU_MAP[vm]

for vmss in $vmss
  AZURE_VMS_VCPU+=VM_SKU_vCPU_MAP[vm] * vmss.capacity

echo "Azure VMs vCPU:         $AZURE_VMS_VCPU"
echo "Azure VMSS vCPU:        $AZURE_VMSS_VCPU"

echo "Total vCPU:   $(($AZURE_VMS_VCPU + $AZURE_VMSS_VCPU))"