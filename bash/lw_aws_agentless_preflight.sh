#!/bin/bash
#
# Preflight check for Lacework Agentless Workload monitoring
# Requires awscli and jq
# You can also run this in AWS Cloudshell where these are preinstalled.

OK="✅"
NO="❌"
WARN="⚠️"

COMPUTE_ONLY=false
DEBUG=false
DOC="
Usage:
  lw_aws_agentless_preflight.sh [-c] [-d] [-p <AWS CLI Profile>]

Options:
  -c   Only select regions which have EC2 compute instances deployed.
  -d   Enable debug messaging (set -x).
  -p   Specify an AWS CLI profile to use when running the script.
"

usage() { echo "$DOC" 1>&2; exit 1; }

while getopts "cdp:" opt; do
    case ${opt} in
        d) DEBUG=true;;
        c) COMPUTE_ONLY=true;;
        p) AWS_PROFILE=$OPTARG;;
        *) usage;;
    esac
done
shift $((OPTIND -1))

if [ $DEBUG = true ]; then
  set -x
fi

echo "********************************************"
echo "     Lacework Agentless Preflight Check"
echo "********************************************"

function hasEcsRole () {
  aws iam list-roles | jq -r '.Roles[] | select(.RoleName == "AWSServiceRoleForECS")'
}

function hasStackSetAdministrationRole () {
  aws iam list-roles | jq -r '.Roles[] | select(.RoleName == "AWSCloudFormationStackSetAdministrationRole")'
}

function hasStackSetExecutionRole () {
  aws iam list-roles | jq -r '.Roles[] | select(.RoleName == "AWSCloudFormationStackSetExecutionRole")'
}

function hasSelfManagedRoles() {
  if [[ ! -z $(hasStackSetAdministrationRole) ]] && [[ ! -z $(hasStackSetExecutionRole) ]]
  then
    echo "Self Managed Roles Exist"
  fi
}

function getEnabledRegions () {
  aws ec2 describe-regions --all-regions | jq -r '.Regions[] | select(.OptInStatus != "not-opted-in") | .RegionName'
}

function checkStatusByRegion () {
  for row in $(echo $2 | jq -r '.[] | del(.metadata) | @base64'); do
    
    local r=$(echo ${row} | base64 --decode | jq -r '.region')
    local s=$(echo ${row} | base64 --decode | jq -r '.status')

    if [ $r == "${1}" ]; then
      echo $s
      return
    fi
  done
}

}

function getSessionToken () {
  aws sts get-session-token --region $region 2> /dev/null | jq -r '.Credentials.Expiration'
}

function getVpcQuotaStatus () {
  aws support describe-trusted-advisor-check-result --check-id jL7PP0l7J9 2> /dev/null | jq -cr '.result.flaggedResources | del(.[].metadata)'
}

function getVpcIntGatewayQuotaStatus () {
  aws support describe-trusted-advisor-check-result --check-id kM7QQ0l7J9 2> /dev/null | jq -cr '.result.flaggedResources | del(.[].metadata)'
}

function getEc2Instances () {
  aws ec2 describe-instances --region $region | jq -r '.Reservations[]'
}

function printOutput () {
  echo ""
  echo "********************************************"
  echo "    Lacework Agentless Preflight Results"
  echo "--------------------------------------------"
  echo ""
  echo "Deploy Self Managed Permissions? $RESULT_SELF_MANAGED_DEPLOY"
  echo "Deploy ECS Service Linked Role?  $RESULT_ECS_ROLE_DEPLOY"
  echo ""
  echo "Recommended Deployment Regions:"
  echo "${RESULT_REGIONS%,*}"
  echo "********************************************"
}

result=$(hasSelfManagedRoles)
if [[ ! -z $result ]]; then
  echo "${OK}  Cloudformation StackSet 'Self-Managed' roles exist."
  RESULT_SELF_MANAGED_DEPLOY="No"
else
  echo "${WARN}  Cloudformation StackSet 'Self-Managed' roles do not exist."
  RESULT_SELF_MANAGED_DEPLOY="Yes"
fi

result=$(hasEcsRole)
if [[ ! -z $result ]]; then
  echo "${OK}  ECS Service Linked role already exists."
  RESULT_ECS_ROLE_DEPLOY="No"
else
  echo "${WARN}  ECS Service Linked role does not exist."
  RESULT_ECS_ROLE_DEPLOY="Yes"
fi

RESULT_REGIONS=""
vpcQuotaStatuses="$(getVpcQuotaStatus)"
vpcIntGatewayQuotaStatuses="$(getVpcIntGatewayQuotaStatus)"
echo "Gathering enabled regions..."
for region in $(getEnabledRegions); do

  echo "Checking AWS region $region..."

  skip=false

  # Check that STS is enabled
  if [[ -z $(getSessionToken $region) ]]; then
    echo "${NO}  STS Service"
    skip=true
  fi

  # Check VPC Quota
  status=$(checkStatusByRegion $region $vpcQuotaStatuses)
  if [[ ! -z $status ]] && [[ $status == "error" ]]; then
    echo "${NO}  VPC Quota is at limit, excluding region."
    skip=true
  elif [[ ! -z $status ]] && [[ $status == "warning" ]]; then
    echo "${WARN}  VPC Quota is close to limit."
  fi
  
  # Check Internet Gateway Quota
  status=$(checkStatusByRegion $region $vpcIntGatewayQuotaStatuses)
  if [[ ! -z $status ]] && [[ $status == "error" ]]; then
    echo "${NO}  Internet Gateway Quota is at limit, excluding region."
    skip=true
  elif [[ ! -z $status ]] && [[ $status == "warning" ]]; then
    echo "${WARN}  Internet Gateway Quota is close to limit."
  fi

  # Check if Compute exists
  if [ $COMPUTE_ONLY = true ]; then
    instances=$(getEc2Instances $region)
    if [[ -z $instances ]]; then
      echo "${WARN}  No compute instances were detected, excluding region."
      skip=true
    fi
  fi

  if [[ $skip = true ]];then
    continue
  fi

  RESULT_REGIONS="$RESULT_REGIONS$region,"

done

printOutput