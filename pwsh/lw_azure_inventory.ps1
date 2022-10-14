#!/usr/local/bin/pwsh
# Script to fetch Azure inventory for Lacework sizing.
# Requirements: az cli

# This script can be run from Azure Cloud Shell.
param
(
    [CmdletBinding()]
    [bool]$json = $false,

    # enable verbose output
    [CmdletBinding()]
    [bool]$v = $false
)

function getSum([int[]]$field) {
    $($field | Measure-Object -Sum).Sum
}

function flatten($fields) {
    [int[]]@($fields | ForEach-Object { $_ })
}

function getSummary([psobject[]]$report) {
    Write-Host "`r`nSummary"
    Write-Host "===================="
    Write-Host "Azure VMs:      $(getSum($report.AZURE_VMS))"
    Write-Host "Azure VMSS:     $(getSum($report.VM_SCALE_SETS))"
    Write-Host "SQL Servers:    $(getSum($report.SQL_SERVERS))"
    Write-Host "Load Balancers: $(getSum($report.LOAD_BALANCERS))"
    Write-Host "Vnet Gateways:  $(getSum($report.GATEWAYS))"
    Write-Host "===================="
    Write-Host "Total Resources: $(getSum(flatten($report.AZURE_VMS, $report.VM_SCALE_SETS, $report.SQL_SERVERS, $report.LOAD_BALANCERS, $report.GATEWAYS)))"
}

function getSubscriptions {
    $subscriptions = &az account list | ConvertFrom-Json | Where-Object { $_.State -eq 'Enabled' }

    $subscriptions | Add-Member -MemberType NoteProperty -Name "AZURE_VMS" -Value 0
    $subscriptions | Add-Member -MemberType NoteProperty -Name "VM_SCALE_SETS" -Value 0
    $subscriptions | Add-Member -MemberType NoteProperty -Name "SQL_SERVERS" -Value 0
    $subscriptions | Add-Member -MemberType NoteProperty -Name "LOAD_BALANCERS" -Value 0
    $subscriptions | Add-Member -MemberType NoteProperty -Name "GATEWAYS" -Value 0

    $subscriptions | Add-Member -MemberType ScriptMethod -Name setSubscription -Value { &az account set --subscription $this.id }
    $subscriptions | Add-Member -MemberType ScriptMethod -Name getResourceGroups -Value { &az group list | ConvertFrom-Json | Select-Object -ExpandProperty name }
    $subscriptions | Add-Member -MemberType ScriptMethod -Name getVMs -Value { $this.AZURE_VMS = $(&az vm list -d --query "[?powerState=='VM running']" | ConvertFrom-Json).Count }
    $subscriptions | Add-Member -MemberType ScriptMethod -Name getVMScaleSets -Value { $this.VM_SCALE_SETS = $(&az vmss list  --query "[].sku.capacity" | ConvertFrom-Json).Count }
    $subscriptions | Add-Member -MemberType ScriptMethod -Name getSQLServers -Value { $this.SQL_SERVERS = $(&az sql server list | ConvertFrom-Json).Count }
    $subscriptions | Add-Member -MemberType ScriptMethod -Name getLoadBalancers -Value { $this.LOAD_BALANCERS = $(&az network lb list | ConvertFrom-Json).Count }
    $subscriptions | Add-Member -MemberType ScriptMethod -Name getGateways -Value { $this.GATEWAYS = $(&az graph query -q "Resources | where type =~ 'Microsoft.Network/virtualNetworkGateways' | summarize count=count()" | ConvertFrom-Json).data.count }

    return $subscriptions
}

# Microsoft.Network/virtualNetworkGateways
# need to run this to avoid an interactive prompt to use the resource graph extension
# -- dump output to null as it currently warns that "az config" is experimental...
az config set extension.use_dynamic_install=yes_without_prompt *> $null
$subscriptions = getSubscriptions

foreach ($s in $subscriptions) {
    Try {
        Write-Host "Getting Inventory of [$($s.name)]..." -NoNewline
        $s.setSubscription()

        $s.getVMs()
        $s.getVMScaleSets()
        $s.getSQLServers()
        $s.getLoadBalancers()
        $s.getGateways()

        Write-Host "DONE!" -ForegroundColor Green
    }

    Catch {
        Write-Host "Failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host @"
######################################################################
Lacework inventory collection complete.
"@

$report = $subscriptions | Select-Object -Property name, id, AZURE_VMS, VM_SCALE_SETS, SQL_SERVERS, LOAD_BALANCERS, GATEWAYS

if ($json){
    $report | ConvertTo-Json
}else{
    $report | Format-Table
    getSummary($report)
}