#!/bin/bash
# Script to fetch Azure inventory for Lacework sizing.
# Requirements: az cli

# This script can be run from Azure Cloud Shell.
param
(
    [CmdletBinding()]
    [bool] $json = $false,

    # enable verbose output
    [CmdletBinding()]
    [bool] $v = $false
)

# Set the initial counts to zero.
$AZURE_VMS=0
$SQL_SERVERS=0
$LOAD_BALANCERS=0
$GATEWAYS=0

function getVMs {
  $(az vm list -d --query "[?powerState=='VM running']" | ConvertFrom-Json).Count
}

function getSQLServers {
  $(az sql server list | ConvertFrom-Json).Count
}

function getLoadBalancers {
  $(az network lb list | ConvertFrom-Json).Count
}

write-host "Starting inventory check."
write-host "Fetching VMs..."
$vms=$(getVMs)
$AZURE_VMS=$(($AZURE_VMS + $vms))

write-host "Fetching SQL Databases..."
$sql=$(getSQLServers)
$SQL_SERVERS=$(($SQL_SERVERS + $sql))

write-host "Fetching Load Balancers..."
$lbs=$(getLoadBalancers)
$LOAD_BALANCERS=$(($LOAD_BALANCERS + $lbs))

write-host "Fetching Gateways..."
#TODO -- replace this with a resource graph query...
# Microsoft.Network/virtualNetworkGateways
# need to run this to avoid an interactive prompt to use the resource graph extension
az config set extension.use_dynamic_install=yes_without_prompt
$GATEWAYS= $(az graph query -q "Resources | where type =~ 'Microsoft.Network/virtualNetworkGateways' | summarize count=count()" | ConvertFrom-Json).data.count


write-output "######################################################################"
write-output "Lacework inventory collection complete."
write-output ""
write-output "Azure VMs:         $AZURE_VMS"
write-output "SQL Servers:       $SQL_SERVERS"
write-output "Load Balancers:    $LOAD_BALANCERS"
write-output "Vnet Gateways:     $GATEWAYS"
write-output "===================="
write-output "Total Resources:   $(($AZURE_VMS + $SQL_SERVERS + $LOAD_BALANCERS + $GATEWAYS))"
