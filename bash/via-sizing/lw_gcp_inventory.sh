#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

# Script to fetch GCP inventory for Lacework sizing.
# Requirements: gcloud, jq

# This script can be run from Google Cloud Shell.

while getopts ":f:o:p:" opt; do
  case ${opt} in
    f )
      FOLDER=$OPTARG
      ;;
    o )
      ORGANIZATION=$OPTARG
      ;;
    p )
      PROJECT=$OPTARG
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
GCE_VCPU=0
#GKE_VCPU=0

###################################

# TODO: Functions to manage key/value mapping
# difference between zsh, bash4, bash3
# zsh v bash4, syntax
# bash3, use a temp file
# --  start with lowest common denominator (file) and expand to leverage native shell capabilities if needed/desired


echo "Retrieving organization info..."
organizations=$(gcloud organizations list --format json | jq -r '.[].name')
echo $organizations
echo "Organization(s) identified."

for org in $organizations;
do
  # get all instances within the organization
  instances=$(gcloud asset search-all-resources --scope=$org --asset-types="compute.googleapis.com/Instance" --format=json)

  # get a map of `{count} {machine_type}` for the organization
  machine_count_map=$(echo $instances | jq -r '.[] | .additionalAttributes.machineType' | sort | uniq -c )

  # make the for loop split on newline vs. space
  IFS=$'\n' 
  # for each entry in the map, get the vCPU value for the type and aggregate the values
  for machine_data in $machine_count_map; 
  do
    machine_data=$(echo $machine_data | tr -s ' ') # trim all but one leading space
    count=$(echo $machine_data | cut -d ' ' -f 2)  # split and take the second value (count)
    machine_type=$(echo $machine_data | cut -d ' ' -f 3) # split and take third value (machine_type)
    type_vcpu_value=$(gcloud compute machine-types describe $machine_type --format=json | jq -r '.guestCpus') # get vCPU for machine type

    GCE_VCPU=$(($GCE_VCPU + (($count * $type_vcpu_value)))) # increment total count
  done


echo "vCPU for Organization $org:   $GCE_VCPU"
done


echo "######################################################################"
echo "Lacework inventory collection complete."
echo ""
#echo "GCE vCPU:   $GCE_VCPU"
#echo "GKE Instances:   $GKE_VCPU"
echo "===================="
echo "Total vCPU: $(($GCE_VCPU))"
