#!/bin/bash

set -o errexit
set -o pipefail

# Script to fetch GCP inventory for Lacework sizing.
# Requirements: gcloud, jq

# This script can be run from Google Cloud Shell.

while getopts ":f:o:p:" opt; do
  case ${opt} in
    f )
      FOLDERS=$OPTARG
      ;;
    o )
      ORGANIZATIONS=$OPTARG
      ;;
    p )
      PROJECTS=$OPTARG
      ;;
    \? )
      printf "Usage: ./lw_gcp_inventory.sh [-f folder] [-o organization] [-p project] \nAny single scope can have multiple values comma delimited, but multiple scopes cannot be defined.\n" 1>&2
      exit 1
      ;;
    : )
      printf "Usage: ./lw_gcp_inventory.sh [-f folder] [-o organization] [-p project] \nAny single scope can have multiple values comma delimited, but multiple scopes cannot be defined.\n" 1>&2
      exit 1
      ;;
  esac
done
shift $((OPTIND -1))

# Set the initial counts to zero.
TOTAL_GCE_VCPU=0
TOTAL_GCE_VM_COUNT=0
TOTAL_PROJECTS=0

function analyzeProject {
  local project=$1
  local projectVCPUs=0
  local projectVmCount=0
  TOTAL_PROJECTS=$(($TOTAL_PROJECTS + 1))

  # get all instances within the scope and turn into a map of `{count} {machine_type}`
  local instanceMap=$(gcloud compute instances list --project $project --quiet --format=json | jq -r '.[] | select(.status != ("TERMINATED")) | .machineType' | sort | uniq -c)

  # make the for loop split on newline vs. space
  IFS=$'\n' 
  # for each entry in the map, get the vCPU value for the type and aggregate the values
  for instance in $instanceMap; 
  do
    local instance=$(echo $instance | tr -s ' ') # trim all but one leading space
    local count=$(echo $instance | cut -d ' ' -f 2)  # split and take the second value (count)
    local machineTypeUrl=$(echo $instance | cut -d ' ' -f 3) # split and take third value (machine_type)
    
    local location=$(echo $machineTypeUrl | cut -d "/" -f9) # extract location from url
    local machineType=$(echo $machineTypeUrl | cut -d "/" -f11) # extract machine type from url
    local typeVCPUValue=$(gcloud compute machine-types describe $machineType --zone=$location --project=$project --format=json | jq -r '.guestCpus') # get vCPU for machine type

    TOTAL_GCE_VCPU=$(($TOTAL_GCE_VCPU + (($count * $typeVCPUValue)))) # increment total count, including Standard GKE
    TOTAL_GCE_VM_COUNT=$(($TOTAL_GCE_VM_COUNT + $count)) # increment total count, including Standard GKE
    projectVCPUs=$(($scopeVCPUs + (($count * $typeVCPUValue)))) # increment total count, including Standard GKE
    projectVmCount=$(($scopeVmCount + $count)) # increment total count, including Standard GKE
  done
  echo "\"$project\", $projectVmCount, $projectVCPUs"
}

function analyzeFolder {
  local folder=$1

  local folders=$(gcloud resource-manager folders list --folder $folder --format=json | jq -r '.[] | .name' | sed 's/.*\///')
  for f in $folders;
  do
    analyzeFolder "$f"
  done

  local projects=$(gcloud projects list --format=json --filter="parent.id=$folder AND parent.type=folder" | jq -r '.[] | .projectId')
  for project in $projects;
  do
    analyzeProject "$project"
  done
}

function analyzeOrganization {
  local organization=$1

  local folders=$(gcloud resource-manager folders list --organization $organization --format=json | jq -r '.[] | .name' | sed 's/.*\///')
  for f in $folders;
  do
    analyzeFolder "$f"
  done

  local projects=$(gcloud projects list --format=json --filter="parent.id=$organization AND parent.type=organization" | jq -r '.[] | .projectId')
  for project in $projects;
  do
    analyzeProject "$project"
  done
}

echo \"Project\", \"VM Count\", \"vCPUs\"

if [ -n "$FOLDERS" ]
then
  for FOLDER in $(echo $FOLDERS | sed "s/,/ /g")
  do
    analyzeFolder "$FOLDER"
  done
elif [ -n "$ORGANIZATIONS" ]
then
  for ORGANIZATION in $(echo $ORGANIZATIONS | sed "s/,/ /g")
  do
    analyzeOrganization "$ORGANIZATION"
  done
elif [ -n "$PROJECTS" ]
then
  for PROJECT in $(echo $PROJECTS | sed "s/,/ /g")
  do
    analyzeProject "$PROJECT"
  done
else
  foundProjects=$(gcloud projects list --format json | jq -r ".[] | .projectId")
  for foundProject in $foundProjects;
  do
    analyzeProject "$foundProject"
  done
fi


echo "##########################################"
echo "Lacework inventory collection complete."
echo ""
echo "License Summary:"
echo "================================================"
echo "Projects analyzed:                     $TOTAL_PROJECTS"
echo "Number of VMs, including standard GKE: $TOTAL_GCE_VM_COUNT"
echo "vCPUs:                                 $TOTAL_GCE_VCPU"
