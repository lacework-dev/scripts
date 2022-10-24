#!/bin/bash
# Script to fetch Azure inventory for Lacework sizing.
# Requirements: az cli, jq, cut, grep, zsh or bash 4+

# This script can be run from Azure Cloud Shell.

# Set the initial counts to zero.

#TODO: future state, support a flag to filter on subscription or management group scope

AZURE_VMS_VCPU=0
AZURE_VMSS_VCPU=0

echo "Building Azure VM SKU to vCPU map..."
az vm list-skus |\
  jq -r '.[] | .name as $parent | select(.capabilities != null) | .capabilities[] | select(.name == "vCPUs") | $parent+":"+.value' |\
  sort | uniq > ./tmp_map 
echo "Map built successfully."
###################################

# No need to iterate subscriptions when using Azure Resource Graph -- this will populate for all subscriptions the user has access to!

# get VM details
echo "Running Az Resource Graph Query for VMs..."
vms=$(az graph query -q "Resources | where type=~'microsoft.compute/virtualmachines' | project subscriptionId, name, sku=properties.hardwareProfile.vmSize")
echo "VM data retrieved."

# tally up VM vCPU 
VM_LINES=$(echo $vms | jq -r '.data[] | .sku')
if [[ ! -z $VM_LINES ]]
then
  while read i; do
    # lookup the vCPU in the map, extract the value
    vCPU=$(grep $i ./tmp_map | cut -d: -f2)
    if [[ ! -z $vCPU ]]
    then
      AZURE_VMS_VCPU=$(($AZURE_VMS_VCPU + $vCPU))
    fi
  done <<< "$VM_LINES"
fi
echo "Azure VMs vCPU:         $AZURE_VMS_VCPU"
echo ""
###################################


# get VMSS details
echo "Running Az Resource Graph Query for VMSS..."
vmss=$(az graph query -q "Resources | where type=~ 'microsoft.compute/virtualmachinescalesets' | project subscriptionId, name, sku=sku.name, capacity = toint(sku.capacity)")
echo "VMSS data retrieved."

# tally up VMSS vCPU -- using a here string to populate the while loop
VMSS_LINES=$(echo $vmss | jq -r '.data[] | .sku+":"+(.capacity|tostring)')
if [[ ! -z $VMSS_LINES ]]
then
  while read i; do
    sku=$(echo $i | cut -d: -f1)
    capacity=$(echo $i | cut -d: -f2)

    vCPU=$(grep $sku ./tmp_map | cut -d: -f2)
    if [[ ! -z $vCPU ]]
    then
      total_vCPU=$(($vCPU * $capacity))

      AZURE_VMSS_VCPU=$(($AZURE_VMSS_VCPU + $total_vCPU))
    fi
  done <<< "$VMSS_LINES"
fi
echo "Azure VMSS vCPU:        $AZURE_VMSS_VCPU"
echo ""
###################################


echo "Total Azure vCPU:       $(($AZURE_VMS_VCPU + $AZURE_VMSS_VCPU))"
rm ./tmp_map