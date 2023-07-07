#!/bin/bash

# Run ./lw_gcp_inventory.sh -h for help on how to run the script.
# Or just read the text in showHelp below.
# Requirements: gcloud, jq

function showHelp {
  echo "lw_gcp_inventory.sh is a tool for estimating license vCPUs in a GCP environment, based on folder,"
  echo "project or organization level. It leverages the gcp CLI and by default analyzes all project a user"
  echo "has access to. The script provides output in a CSV format to be imported into a spreadsheet, as"
  echo "well as an easy-to-read summary."
  echo ""
  echo "By default, the script will scan all projects returned by the following command:"
  echo "gcloud projects list"
  echo ""
  echo "Note the following about the script:"
  echo "* Works great in a cloud shell"
  echo "* It has been verified to work on Mac and Linux based systems"
  echo "* Has been observed to work with Windows Subsystem for Linux to run on Windows"
  echo "* Run using the following syntax: ./lw_gcp_inventory.sh, sh lw_gcp_inventory.sh will not work"
  echo ""
  echo "Available flags:"
  echo " -p       Comma separated list of GCP projects to scan."
  echo "          ./lw_gcp_inventory.sh -p project-1,project-2"
  echo " -f       Comma separated list of GCP folders to scan."
  echo "          ./lw_gcp_inventory.sh -p 1234,456"
  echo " -o       Comma separated list of GCP organizations to scan."
  echo "          ./lw_gcp_inventory.sh -o 1234,456"
}

#Ensure the script runs with the BASH shell
echo $BASH | grep -q "bash"
if [ $? -ne 0 ]
then
  echo The script is running using the incorrect shell.
  echo Use ./lw_gcp_inventory.sh to run the script using the required shell, bash.
  exit
fi

set -o errexit
set -o pipefail

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
      showHelp
      exit 1
      ;;
    : )
      showHelp
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
  local instanceList=$(gcloud compute instances list --project $project --quiet --format=json 2>&1)
  if [[ $instanceList = [* ]] 
  then
    local instanceMap=$(echo $instanceList | jq -r '.[] | select(.status != ("TERMINATED")) | .machineType' | sort | uniq -c)
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

      projectVCPUs=$(($projectVCPUs + (($count * $typeVCPUValue)))) # increment total count, including Standard GKE
      projectVmCount=$(($projectVmCount + $count)) # increment total count, including Standard GKE
    done

    TOTAL_GCE_VCPU=$(($TOTAL_GCE_VCPU + $projectVCPUs)) # increment total count, including Standard GKE
    TOTAL_GCE_VM_COUNT=$(($TOTAL_GCE_VM_COUNT + $projectVmCount)) # increment total count, including Standard GKE
  elif [[ $instanceList == *"SERVICE_DISABLED"* ]]
  then
    projectVmCount="\"INFO: Compute instance API disabled\""
  elif [[ $instanceList == *"PERMISSION_DENIED"* ]]
  then
    projectVmCount="\"INFO: Data not available. Permission denied\""
  else
    projectVmCount="\"ERROR: Failed to load instance information: $instanceList\""
  fi
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
