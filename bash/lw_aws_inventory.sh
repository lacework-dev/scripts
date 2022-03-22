#!/bin/bash
# Script to fetch AWS inventory for Lacework sizing.
# Requirements: awscli, jq

# You can specify a profile with the -p flag, or get JSON output with the -j flag.
# Note:
# 1. You can specify multiple accounts by passing a comma seperated list, e.g. "default,qa,test",
# there are no spaces between accounts in the list
# 2. The script takes a while to run in large accounts with many resources, the final count is an aggregation of all resources found.
# 3. You can use aws organizations to import a list of all of your connected accounts using the o flag.

# Need to modify the IFS value to account for spaces in names
# Save any existing IFS values in the placeholder
IFSPLACEHOLDER=$IFS
AWS_PROFILE=default
export AWS_MAX_ATTEMPTS=20

# Usage: ./lw_aws_inventory.sh
while getopts ":jop:" opt; do
  case ${opt} in
    o )
      # The jq parsing from aws organizations output will yield newline delims
      # Need to modify the IFS to account for that
      IFS=$'\n'
      AWS_PROFILE=$(aws organizations list-accounts | jq .[] | jq .[] | jq .Name)
      ;;
    p )
      # Need to set the IFS to split only on commas
      IFS=,
      AWS_PROFILE=$OPTARG
      ;;
    j )
      JSON="true"
      ;;
    \? )
      echo "Usage: ./lw_aws_inventory.sh [-p profile] [-j]" 1>&2
      exit 1
      ;;
    : )
      echo "Usage: ./lw_aws_inventory.sh [-p profile] [-j]" 1>&2
      exit 1
      ;;
  esac
done
shift $((OPTIND -1))

# Set the initial counts to zero.
EC2_INSTANCES=0
RDS_INSTANCES=0
REDSHIFT_CLUSTERS=0
ELB_V1=0
ELB_V2=0
NAT_GATEWAYS=0
ECS_FARGATE_CLUSTERS=0
ECS_FARGATE_RUNNING_TASKS=0
LAMBDA_FNS=0
LAMBDA_FNS_EXIST="No"

function getRegions {
  aws --profile $profile ec2 describe-regions --output json | jq -r '.[] | .[] | .RegionName'
}

function getInstances {
  aws --profile $profile ec2 describe-instances --query 'Reservations[*].Instances[*].[InstanceId]' --filters Name=instance-state-name,Values=running,stopped --region $r --output json --no-paginate | jq 'flatten | length'
}

function getRDSInstances {
  aws --profile $profile rds describe-db-instances --region $r --output json --no-paginate | jq '.DBInstances | length'
}

function getRedshift {
  aws --profile $profile redshift describe-clusters --region $r --output json --no-paginate | jq '.Clusters | length'
}

function getElbv1 {
  aws --profile $profile elb describe-load-balancers --region $r  --output json --no-paginate | jq '.LoadBalancerDescriptions | length'
}

function getElbv2 {
  aws --profile $profile elbv2 describe-load-balancers --region $r --output json --no-paginate | jq '.LoadBalancers | length'
}

function getNatGateways {
  aws --profile $profile ec2 describe-nat-gateways --region $r --output json --no-paginate | jq '.NatGateways | length'
}

function getECSFargateClusters {
  aws --profile $profile ecs list-clusters --region $r --output json --no-paginate | jq -r '.clusterArns[]'
}

function getECSFargateRunningTasks {
  RUNNING_FARGATE_TASKS=0
  for c in $ecsfargateclusters; do
    allclustertasks=$(aws --profile $profile ecs list-tasks --region $r --output json --cluster $c --no-paginate | jq -r '.taskArns | join(" ")')
    if [ -n "${allclustertasks}" ]; then
      fargaterunningtasks=$(aws --profile $profile ecs describe-tasks --region $r --output json --tasks $allclustertasks --cluster $c --no-paginate | jq '[.tasks[] | select(.launchType=="FARGATE") | .containers[] | select(.lastStatus=="RUNNING")] | length')
      RUNNING_FARGATE_TASKS=$(($RUNNING_FARGATE_TASKS + $fargaterunningtasks))
    fi
  done

  echo "${RUNNING_FARGATE_TASKS}"
}


function getLambdaFunctions {
  aws --profile $profile lambda list-functions --region $r --output json --no-paginate | jq '.Functions | length'
}

function calculateInventory {
  profile=$1
  for r in $(getRegions); do
    if [ "$JSON" != "true" ]; then
      echo $r
    fi
    instances=$(getInstances $r $profile)
    EC2_INSTANCES=$(($EC2_INSTANCES + $instances))

    rds=$(getRDSInstances $r $profile)
    RDS_INSTANCES=$(($RDS_INSTANCES + $rds))

    redshift=$(getRedshift $r $profile)
    REDSHIFT_CLUSTERS=$(($REDSHIFT_CLUSTERS + $redshift))

    elbv1=$(getElbv1 $r $profile)
    ELB_V1=$(($ELB_V1 + $elbv1))

    elbv2=$(getElbv2 $r $profile)
    ELB_V2=$(($ELB_V2 + $elbv2))

    natgw=$(getNatGateways $r $profile)
    NAT_GATEWAYS=$(($NAT_GATEWAYS + $natgw))

    ecsfargateclusters=$(getECSFargateClusters $r $profile)
    ecsfargateclusterscount=$(echo $ecsfargateclusters | wc -w)
    ECS_FARGATE_CLUSTERS=$(($ECS_FARGATE_CLUSTERS + $ecsfargateclusterscount))

    ecsfargaterunningtasks=$(getECSFargateRunningTasks $r $ecsfargateclusters $profile)
    ECS_FARGATE_RUNNING_TASKS=$(($ECS_FARGATE_RUNNING_TASKS + $ecsfargaterunningtasks))

    lambdafns=$(getLambdaFunctions $r $profile)
    LAMBDA_FNS=$(($LAMBDA_FNS + $lambdafns))
    if [ $LAMBDA_FNS -gt 0 ]; then LAMBDA_FNS_EXIST="Yes"; fi
done

TOTAL=$(($EC2_INSTANCES + $RDS_INSTANCES + $REDSHIFT_CLUSTERS + $ELB_V1 + $ELB_V2 + $NAT_GATEWAYS))
}

function textoutput {
  echo "######################################################################"
  echo "Lacework inventory collection complete."
  echo ""
  echo "EC2 Instances:     $EC2_INSTANCES"
  echo "RDS Instances:     $RDS_INSTANCES"
  echo "Redshift Clusters: $REDSHIFT_CLUSTERS"
  echo "v1 Load Balancers: $ELB_V1"
  echo "v2 Load Balancers: $ELB_V2"
  echo "NAT Gateways:      $NAT_GATEWAYS"
  echo "===================="
  echo "Total Resources:   $TOTAL"
  echo ""
  echo "Fargate Information"
  echo "===================="
  echo "ECS Fargate Clusters:                 $ECS_FARGATE_CLUSTERS"
  echo "ECS Fargate Running Containers/Tasks: $ECS_FARGATE_RUNNING_TASKS"
  echo ""
  echo "Additional Serverless Inventory Details (NOT included in Total Resources count above):"
  echo "===================="
  echo "Lambda Functions Exist:         $LAMBDA_FNS_EXIST"
}

function jsonoutput {
  echo "{"
  echo "  \"ec2\": \"$EC2_INSTANCES\","
  echo "  \"rds\": \"$RDS_INSTANCES\","
  echo "  \"redshift\": \"$REDSHIFT_CLUSTERS\","
  echo "  \"v1_lb\": \"$ELB_V1\","
  echo "  \"v2_lb\": \"$ELB_V2\","
  echo "  \"nat_gw\": \"$NAT_GATEWAYS\","
  echo "  \"total\": \"$TOTAL\","
  echo "  \"_ecs_fargate_clusters\": \"$ECS_FARGATE_CLUSTERS\","
  echo "  \"_ecs_fargate_running_tasks_containers\": \"$ECS_FARGATE_RUNNING_TASKS\","
  echo "  \"_lambda_functions_exist\": \"$LAMBDA_FNS_EXIST\""
  echo "}"
}

# Get the number of accounts to iterate over
PROFCOUNT=0
for PROFILE in $AWS_PROFILE
do
  PROFCOUNT=$(($PROFCOUNT + 1))
done

# Start an iterator to track progress
CURRENT=0
for PROFILE in $AWS_PROFILE
do
    CURRENT=$(($CURRENT + 1))
    # Need to strip the quotes
    PROFILE=$(echo $PROFILE | sed 's/"//g')
    echo "Working on" $PROFILE $CURRENT"/"$PROFCOUNT
    calculateInventory $PROFILE
done

# Reset IFS to whatever it was before we started
IFS=$IFSPLACEHOLDER

if [ "$JSON" == "true" ]; then
  jsonoutput
else
  textoutput
fi
