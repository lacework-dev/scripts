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
      echo "Usage: ./lw_gcp_inventory.sh [-f folder] [-o organization] [-p project] \nAny single scope can have multiple values comma delimited, but multiple scopes cannot be defined." 1>&2
      exit 1
      ;;
    : )
      echo "Usage: ./lw_gcp_inventory.sh [-f folder] [-o organization] [-p project] \nAny single scope can have multiple values comma delimited, but multiple scopes cannot be defined." 1>&2
      exit 1
      ;;
  esac
done
shift $((OPTIND -1))

# Set the initial counts to zero.
TOTAL_GCE_VCPU=0
TOTAL_GCE_VM_COUNT=0

function retrieveConsumptionData {
  local scope=$1
  local scopeDescription=$2
  local scopeVCPUs=0
  local scopeVmCount=0
  #echo retrieveConsumptionData $1 $2

  # get all instances within the scope
  local instances=$(gcloud asset search-all-resources --scope=$scope --asset-types="compute.googleapis.com/Instance" --format=json)

  # get a map of `{count} {machine_type}` for the scope that are not terminated / stopped
  local machine_count_map=$(echo $instances | jq -r '.[] | select(.state != ("TERMINATED")) | .additionalAttributes.machineType + " " + .location + " " + .project' | sort | uniq -c )
  
  #Read project information that's within scope for this mapping
  local projects=$(gcloud asset search-all-resources --scope=$scope --asset-types="compute.googleapis.com/Project" --format=json)

  # make the for loop split on newline vs. space
  IFS=$'\n' 
  # for each entry in the map, get the vCPU value for the type and aggregate the values
  for machine_data in $machine_count_map; 
  do
    local machine_data=$(echo $machine_data | tr -s ' ') # trim all but one leading space
    local count=$(echo $machine_data | cut -d ' ' -f 2)  # split and take the second value (count)
    local machine_type=$(echo $machine_data | cut -d ' ' -f 3) # split and take third value (machine_type)
    local location=$(echo $machine_data | cut -d ' ' -f 4) # split and take fourth value (location)
    local projectId=$(echo $machine_data | cut -d ' ' -f 5) # split and take fifth value (project)
    local project=$(echo $projects | jq -r --arg projectId "$projectId" '.[] | select(.project==$projectId) | .displayName')
    local type_vcpu_value=$(gcloud compute machine-types describe $machine_type --zone=$location --project=$project --format=json | jq -r '.guestCpus') # get vCPU for machine type

    TOTAL_GCE_VCPU=$(($TOTAL_GCE_VCPU + (($count * $type_vcpu_value)))) # increment total count, including Standard GKE
    TOTAL_GCE_VM_COUNT=$(($TOTAL_GCE_VM_COUNT + $count)) # increment total count, including Standard GKE
    scopeVCPUs=$(($scopeVCPUs + (($count * $type_vcpu_value)))) # increment total count, including Standard GKE
    scopeVmCount=$(($scopeVmCount + $count)) # increment total count, including Standard GKE
  done

  echo $scopeDescription
  echo "Number of VMs: $scopeVmCount"
  echo "vCPUs:         $scopeVCPUs"
  echo "######################################################################"
}

if [ -n "$FOLDERS" ]
then
  echo Folders set
  for FOLDER in $(echo $FOLDERS | sed "s/,/ /g")
  do
    #echo $FOLDER
    retrieveConsumptionData "folders/$FOLDER" "Folder: $FOLDER"
  done
elif [ -n "$ORGANIZATIONS" ]
then
  echo Organizations set
  for ORGANIZATION in $(echo $ORGANIZATIONS | sed "s/,/ /g")
  do
    #echo $ORGANIZATION
    retrieveConsumptionData "organizations/$ORGANIZATION" "Organization: $ORGANIZATION"
  done
elif [ -n "$PROJECTS" ]
then
  #echo Projects set
  for PROJECT in $(echo $PROJECTS | sed "s/,/ /g")
  do
    #echo $PROJECT
    retrieveConsumptionData "projects/$PROJECT" "Project: $PROJECT"
  done
else

  foundOrganizations=$(gcloud organizations list --format json | jq -r '.[].name')
  if [ -n "$foundOrganizations" ]
  then
    #echo Found $foundOrganizations
    for foundOrganization in $foundOrganizations;
    do
      #echo $foundOrganization
      retrieveConsumptionData "organizations/$foundOrganization" "Organization: $foundOrganization"
    done
  else
    foundProjects=$(gcloud projects list --format json | jq -r ".[] | .projectId")
    #echo Found $foundProjects
    for foundProject in $foundProjects;
    do
      #echo $foundProject
      retrieveConsumptionData "projects/$foundProject" "Project: $foundProject"
    done
  fi
fi

echo "Lacework inventory collection complete."
echo "Number of VMs: $TOTAL_GCE_VM_COUNT"
echo "vCPUs:         $TOTAL_GCE_VCPU"
