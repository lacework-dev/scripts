#!/bin/bash
# Script to fetch GCP inventory for Lacework sizing.
# Requirements: gcloud, jq

# This script can be run from Google Cloud Shell.

# Set the initial counts to zero.
GCE_INSTANCES=0
GKE_INSTANCES=0
GAE_INSTANCES=0
SQL_INSTANCES=0
LOAD_BALANCERS=0
GATEWAYS=0

# Uncomment and replace with your own list of projects. Otherwise the script
# scans all the projects in your organization. You must use the Project ID.
#PROJECT_IDS=(stitch-dev-289221 stitch-vault stitch-jenkins-288315 stitch-infra)

function getProjects {
  gcloud projects list --format json | jq -r ".[] | .projectId"
}

function isComputeEnabled {
  gcloud services list --format json | jq -r '.[] | .name' | grep -q "compute.googleapis.com"
}

function isAppEngineEnabled {
  if [ `gcloud app operations list --format json | jq length` -gt 0 ]
  then
    return 0
  else
    return 1
  fi
}

# NOTE - it is technically possible to have a CloudSQL instance without the
# sqladmin API enabled; but you cannot check the instance programatically
# without the API enabled
function isCloudSQLEnabled {
  gcloud services list --format json | jq -r '.[] | .name' | grep -q "sqladmin.googleapis.com"
}

function getGKEInstances {
  gcloud compute instances list --format json | jq '[.[] | select(.name | contains("gke-"))] | length'
}

function getGCEInstances {
  gcloud compute instances list --format json | jq '[.[] | select(.name | contains("gke-") | not)] | length'
}

function getGAEInstances {
  gcloud app instances list --format json | jq length
}

function getSQLInstances {
  gcloud sql instances list --format json | jq length
}

function getLoadBalancers {
  gcloud compute forwarding-rules list --format json | jq length
}

function getGateways {
  gcloud compute routers list --format json | jq '[.[] | .nats | length] | add'
}

# Define PROJECT_IDS above to scan a subset of projects. Otherwise we scan
# all of the projects in the organization.
if [[ -z $PROJECT_IDS ]]; then
  PROJECT_IDS=$(getProjects)
fi

# Loop through all the projects and take inventory
for project in ${PROJECT_IDS[@]}; do
  echo ""
  echo "######################################################################"
  echo "Project: $project"
  gcloud config set project $project

  if isComputeEnabled; then
    echo "Checking for compute resources."
    # Update the GCE instances
    gce_inst=$(getGCEInstances)
    GCE_INSTANCES=$(($GCE_INSTANCES + $gce_inst))

    # Update the GKE instances
    gke_inst=$(getGKEInstances)
    GKE_INSTANCES=$(($GKE_INSTANCES + $gke_inst))

    # Update the load balancers
    lbs=$(getLoadBalancers)
    LOAD_BALANCERS=$(($LOAD_BALANCERS + $lbs))

    # Update the gateways
    gateways=$(getGateways)
    GATEWAYS=$(($GATEWAYS + $gateways))
  fi

  # Check if AppEngine is being used
  if isAppEngineEnabled; then
    echo "Checking for AppEngine instances."
    gae_inst=$(getGAEInstances)
    GAE_INSTANCES=$(($GAE_INSTANCES + $gae_inst))
  fi

  # Check for SQL instances
  if isCloudSQLEnabled; then
    echo "Checking for Cloud SQL instances."
    sqls=$(getSQLInstances)
    SQL_INSTANCES=$(($SQL_INSTANCES + $sqls))
  fi
done

echo ""
echo "######################################################################"
echo "Lacework inventory collection complete."
echo ""
echo "GCE Instances:   $GCE_INSTANCES"
echo "GKE Instances:   $GKE_INSTANCES"
echo "GAE Instances:   $GAE_INSTANCES"
echo "Load Balancers:  $LOAD_BALANCERS"
echo "Gateways:        $GATEWAYS"
echo "SQL Instances:   $SQL_INSTANCES"
echo "===================="
echo "Total Resources: $(($GCE_INSTANCES + $GKE_INSTANCES + $GAE_INSTANCES + $LOAD_BALANCERS + $GATEWAYS + $SQL_INSTANCES))"
