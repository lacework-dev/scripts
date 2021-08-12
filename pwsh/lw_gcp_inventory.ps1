#!/bin/bash
# Script to fetch GCP inventory for Lacework sizing.
# Requirements: gcloud, jq
param
(
    [CmdletBinding()]
    [bool] $json = $false,

    # Uncomment and replace with your own list of projects. Otherwise the script
    # scans all the projects in your organization. You must use the Project ID.
    #project_ids=@("stitch-dev-289221","stitch-vault","stitch-jenkins-288315","stitch-infra")
    [CmdletBinding()]
    [array] $project_ids = $null,

    # enable verbose output
    [CmdletBinding()]
    [bool] $v = $false
)

# Set the initial counts to zero.
$global:GCE_INSTANCES=0
$global:GKE_INSTANCES=0
$global:SQL_INSTANCES=0
$global:LOAD_BALANCERS=0
$global:GATEWAYS=0

function getProjects {
  $(gcloud projects list --format json | ConvertFrom-Json).projectId
}

function isComputeEnabled {
  #gcloud services list --format json | jq -r '.[] | .name' | grep -q "compute.googleapis.com"
  $(gcloud services list --format json | ConvertFrom-Json).name -contains "compute.googleapis.com"
}

# NOTE - it is technically possible to have a CloudSQL instance without the 
# sqladmin API enabled; but you cannot check the instance programatically 
# without the API enabled
function isCloudSQLEnabled {
  $(gcloud services list --format json | ConvertFrom-Json).name -contains "sqladmin.googleapis.com" 
}

function getGKEInstances {
  #gcloud compute instances list --format json | jq '[.[] | select(.name | contains("gke-"))] | length'
  $((gcloud compute instances list --format json | ConvertFrom-Json).name | Where-Object {$_ -contains "gke-"}).Count
}

function getGCEInstances {
  #gcloud compute instances list --format json | jq '[.[] | select(.name | contains("gke-") | not)] | length'
  $((gcloud compute instances list --format json | ConvertFrom-Json).name | Where-Object {$_ -notcontains "gke-"}).Count
}

function getSQLInstances {
  $(gcloud sql instances list --format json | ConvertFrom-Json).Count
}

function getLoadBalancers {
  $(gcloud compute forwarding-rules list --format json | ConvertFrom-Json).Count
}

function getGateways {
  #gcloud compute routers list --format json | jq '[.[] | .nats | length] | add'
  $(gcloud compute routers list --format json | ConvertFrom-Json).nats.Count
}

# Define PROJECT_IDS above to scan a subset of projects. Otherwise we scan
# all of the projects in the organization.
if ($project_ids -eq $null){
    $project_ids=$(getProjects)
}

# Loop through all the projects and take inventory
foreach ($project in $project_ids){
  write-host ""
  write-host "######################################################################"
  write-host "Project: $project"
  gcloud config set project $project

  if (isComputeEnabled) {
    write-host "Checking for compute resources."
    # Update the GCE instances
    $gce_inst=$(getGCEInstances)
    $global:GCE_INSTANCES=$(($global:GCE_INSTANCES + $gce_inst))

    # Update the GKE instances
    $gke_inst=$(getGKEInstances)
    $global:GKE_INSTANCES=$(($global:GKE_INSTANCES + $gke_inst))

    # Update the load balancers
    $lbs=$(getLoadBalancers)
    $global:LOAD_BALANCERS=$(($global:LOAD_BALANCERS + $lbs))

    # Update the gateways
    $gateways=$(getGateways)
    $global:GATEWAYS=$(($global:GATEWAYS + $gateways))
  }

  # Check for SQL instances
  if (isCloudSQLEnabled) {
    write-host "Checking for Cloud SQL instances."
    $sqls=$(getSQLInstances)
    $global:SQL_INSTANCES=$(($global:SQL_INSTANCES + $sqls))
  }
}

write-host "######################################################################"
write-host "Lacework inventory collection complete."
write-host ""
write-host "GCE Instances:   $global:GCE_INSTANCES"
write-host "GKE Instances:   $global:GKE_INSTANCES"
write-host "Load Balancers:  $global:LOAD_BALANCERS"
write-host "Gateways:        $global:GATEWAYS"
write-host "SQL Instances:   $global:SQL_INSTANCES"
write-host "===================="
write-host "Total Resources: $(($global:GCE_INSTANCES + $global:GKE_INSTANCES + $global:LOAD_BALANCERS + $global:GATEWAYS + $global:SQL_INSTANCES))"
