#!/bin/bash

# Script to fetch Azure inventory for Lacework sizing.
# Requirements: az cli, jq, cut, grep

# This script can be run from Azure Cloud Shell.

set -o errexit
set -o pipefail

while getopts ":m:s:" opt; do
  case ${opt} in
    s )
      SUBSCRIPTION=$OPTARG
      ;;
    m )
      MANAGEMENT_GROUP=$OPTARG
      ;;
    \? )
      echo "Usage: ./lw_azure_inventory.sh [-m management_group] [-s subscription] \nAny single scope can have multiple values comma delimited, but multiple scopes cannot be defined." 1>&2
      exit 1
      ;;
    : )
      echo "Usage: ./lw_azure_inventory.sh [-m management_group] [-s subscription] \nAny single scope can have multiple values comma delimited, but multiple scopes cannot be defined." 1>&2
      exit 1
      ;;
  esac
done
shift $((OPTIND -1))

function removeMap {
  if [[ -f "./tmp_map" ]]; then
    rm ./tmp_map
  fi
}

function installResourceGraphIfNotPresent {
  resourceGraphPresent=$(az extension list  --query "contains([].name, \`resource-graph\`)")
  if [ "$resourceGraphPresent" != true ] ; then
    echo "resource-graph extension not present in Az CLI installation. Enabling..."
    az extension add --name "resource-graph"
  else
    echo "resource-graph extension already present..."
  fi
}

# set trap to remove tmp_map file regardless of exit status
trap removeMap EXIT


# Set the initial counts to zero.
AZURE_VMS_VCPU=0
AZURE_VMSS_VCPU=0

installResourceGraphIfNotPresent

echo "Building Azure VM SKU to vCPU map..."
az vm list-skus --resource-type virtualmachines |\
  jq -r '.[] | .name as $parent | select(.capabilities != null) | .capabilities[] | select(.name == "vCPUs") | $parent+":"+.value' |\
  sort | uniq > ./tmp_map 
echo "Map built successfully."
###################################

# No need to iterate subscriptions when using Azure Resource Graph -- this will populate for all subscriptions the user has access to!

# get VM details
echo "Running Az Resource Graph Query for VMs..."
# Management group takes precedence...partial scopes ALLOWED
if [[ ! -z "$MANAGEMENT_GROUP" ]]; then
  # use string substitution to replace commas (,) with spaces (' ') for $MANAGEMENT_GROUP
  vms=$(az graph query -q "Resources | where type=~'microsoft.compute/virtualmachines' | project subscriptionId, name, sku=properties.hardwareProfile.vmSize"\
        --management-groups "${MANAGEMENT_GROUP//,/ }" --allow-partial-scopes) 
elif [[ ! -z "$SUBSCRIPTION" ]]; then
  # use string substitution to replace commas (,) with spaces (' ') for $SUBSCRIPTION
  vms=$(az graph query -q "Resources | where type=~'microsoft.compute/virtualmachines' | project subscriptionId, name, sku=properties.hardwareProfile.vmSize"\
        --subscriptions "${SUBSCRIPTION//,/ }" --allow-partial-scopes)
else
  vms=$(az graph query -q "Resources | where type=~'microsoft.compute/virtualmachines' | project subscriptionId, name, sku=properties.hardwareProfile.vmSize")
fi
echo "VM data retrieved."


# tally up VM vCPU 
VM_LINES=$(echo $vms | jq -r '.data[] | .sku')
if [[ ! -z $VM_LINES ]]
then
  while read i; do
    # lookup the vCPU in the map, extract the value
    vCPU=$(grep $i: ./tmp_map | cut -d: -f2)
    if [[ ! -z $vCPU ]]
    then
      AZURE_VMS_VCPU=$(($AZURE_VMS_VCPU + $vCPU))
    fi
  done <<< "$VM_LINES"
fi
echo "Azure VMs vCPU:         $AZURE_VMS_VCPU"
echo ""
###################################


#TODO: future state, support a flag to filter on subscription or management group scope
# get VMSS details
echo "Running Az Resource Graph Query for VMSS..."
# Management group takes precedence...partial scopes ALLOWED
if [[ ! -z "$MANAGEMENT_GROUP" ]]; then
  # use string substitution to replace commas (,) with spaces (' ') for $MANAGEMENT_GROUP
  vmss=$(az graph query -q "Resources | where type=~ 'microsoft.compute/virtualmachinescalesets' | project subscriptionId, name, sku=sku.name, capacity = toint(sku.capacity)"\
        --management-groups "${MANAGEMENT_GROUP//,/ }" --allow-partial-scopes) 
elif [[ ! -z "$SUBSCRIPTION" ]]; then
  # use string substitution to replace commas (,) with spaces (' ') for $SUBSCRIPTION
  vmss=$(az graph query -q "Resources | where type=~ 'microsoft.compute/virtualmachinescalesets' | project subscriptionId, name, sku=sku.name, capacity = toint(sku.capacity)"\
        --subscriptions "${SUBSCRIPTION//,/ }" --allow-partial-scopes)
else
  vmss=$(az graph query -q "Resources | where type=~ 'microsoft.compute/virtualmachinescalesets' | project subscriptionId, name, sku=sku.name, capacity = toint(sku.capacity)")
fi
echo "VMSS data retrieved."

# tally up VMSS vCPU -- using a here string to populate the while loop
VMSS_LINES=$(echo $vmss | jq -r '.data[] | .sku+":"+(.capacity|tostring)')
if [[ ! -z $VMSS_LINES ]]
then
  while read i; do
    sku=$(echo $i | cut -d: -f1)
    capacity=$(echo $i | cut -d: -f2)

    vCPU=$(grep $sku: ./tmp_map | cut -d: -f2)
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
