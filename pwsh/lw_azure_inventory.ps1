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
$global:AZURE_VMS=0
$global:SQL_SERVERS=0
$global:LOAD_BALANCERS=0
$global:GATEWAYS=0

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
$global:AZURE_VMS=$(($global:AZURE_VMS + $vms))

write-host "Fetching SQL Databases..."
$sql=$(getSQLServers)
$global:SQL_SERVERS=$(($global:SQL_SERVERS + $sql))

write-host "Fetching Load Balancers..."
$lbs=$(getLoadBalancers)
$global:LOAD_BALANCERS=$(($global:LOAD_BALANCERS + $lbs))

write-host "Fetching Gateways..."
#TODO -- replace this with a resource graph query...
# Microsoft.Network/virtualNetworkGateways
# need to run this to avoid an interactive prompt to use the resource graph extension
az config set extension.use_dynamic_install=yes_without_prompt
$global:GATEWAYS= $(az graph query -q "Resources | where type =~ 'Microsoft.Network/virtualNetworkGateways' | summarize count=count()" | ConvertFrom-Json).data.count


function textoutput {
  write-output "######################################################################"
  write-output "Lacework inventory collection complete."
  write-output ""
  write-output "Azure VMs:         $global:AZURE_VMS"
  write-output "SQL Servers:       $global:SQL_SERVERS"
  write-output "Load Balancers:    $global:LOAD_BALANCERS"
  write-output "Vnet Gateways:     $global:GATEWAYS"
  write-output "===================="
  write-output "Total Resources:   $(($global:AZURE_VMS + $global:SQL_SERVERS + $global:LOAD_BALANCERS + $global:GATEWAYS))"
}

function jsonoutput {
  write-output "{"
  write-output  "  `"vms`": `"$global:AZURE_VMS`","
  write-output  "  `"sqlservers`": `"$global:SQL_SERVERS`","
  write-output  "  `"lb`": `"$global:LOAD_BALANCERS`","
  write-output  "  `"vnetgw`": `"$global:GATEWAYS`","
  Write-output  "  `"total`": `"$($global:AZURE_VMS + $global:SQL_SERVERS + $global:LOAD_BALANCERS + $global:GATEWAYS)`""
  write-output  "}"
}

if ($json -eq $true){
  jsonoutput
}else{
  textoutput
}