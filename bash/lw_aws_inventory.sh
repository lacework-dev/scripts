#!/bin/bash
# Script to fetch AWS inventory for Lacework sizing.
# Requirements: awscli, jq

# By default this script will try to find your AWS credentials in the environment.

# You can specify a profile with the -p flag
# Get JSON output with the -j flag.
# Note:
# 1. You can specify multiple accounts by passing a comma seperated list, e.g. "default,qa,test",
# there are no spaces between accounts in the list
# 2. The script takes a while to run in large accounts with many resources, the final count is an aggregation of all resources found.


AWS_PROFILE=default

# Usage: ./lw_aws_inventory.sh
while getopts ":p:j" opt; do
  case ${opt} in
    p )
      USE_PROFILE="true"
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
ECS_TASK_DEFINITIONS=0
ECS_FARGATE_ACTIVE_SERVICES=0
LAMBDA_FNS=0

function getRegions {
  aws $AWS_PROFILE_STRING ec2 describe-regions --output json | jq -r '.[] | .[] | .RegionName'
}

function getInstances {
  aws $AWS_PROFILE_STRING ec2 describe-instances --query 'Reservations[*].Instances[*].[InstanceId]' --region $r --output json --no-paginate | jq 'flatten | length'
}

function getRDSInstances {
  aws $AWS_PROFILE_STRING rds describe-db-instances --region $r --output json --no-paginate | jq '.DBInstances | length'
}

function getRedshift {
  aws $AWS_PROFILE_STRING redshift describe-clusters --region $r --output json --no-paginate | jq '.Clusters | length'
}

function getElbv1 {
  aws $AWS_PROFILE_STRING elb describe-load-balancers --region $r  --output json --no-paginate | jq '.LoadBalancerDescriptions | length'
}

function getElbv2 {
  aws $AWS_PROFILE_STRING elbv2 describe-load-balancers --region $r --output json --no-paginate | jq '.LoadBalancers | length'
}

function getNatGateways {
  aws $AWS_PROFILE_STRING ec2 describe-nat-gateways --region $r --output json --no-paginate | jq '.NatGateways | length'
}

function getECSFargateClusters {
  aws $AWS_PROFILE_STRING ecs list-clusters --region $r --output json --no-paginate | jq -r '.clusterArns[]'
}

function getECSTaskDefinitions {
  aws $AWS_PROFILE_STRING ecs list-task-definitions --region $r --output json --no-paginate | jq '.taskDefinitionArns | length'
}

function getECSFargateRunningTasks {
  RUNNING_FARGATE_TASKS=0
  for c in $ecsfargateclusters; do
    allclustertasks=$(aws $AWS_PROFILE_STRING ecs list-tasks --region $r --output json --cluster $c --no-paginate | jq -r '.taskArns | join(" ")')
    if [ -n "${allclustertasks}" ]; then
      fargaterunningtasks=$(aws $AWS_PROFILE_STRING ecs describe-tasks --region $r --output json --tasks $allclustertasks --cluster $c --no-paginate | jq '[.tasks[] | select(.launchType=="FARGATE") | select(.lastStatus=="RUNNING")] | length')
      RUNNING_FARGATE_TASKS=$(($RUNNING_FARGATE_TASKS + $fargaterunningtasks))
    fi
  done

  echo "${RUNNING_FARGATE_TASKS}"
}

function getECSFargateServices {
  ACTIVE_FARGATE_SERVICES=0
  for c in $ecsfargateclusters; do
    allclusterservices=$(aws $AWS_PROFILE_STRING ecs list-services --region $r --output json --cluster $c --no-paginate | jq -r '.serviceArns | join(" ")')
    if [ -n "${allclusterservices}" ]; then
      fargateactiveservices=$(aws $AWS_PROFILE_STRING ecs describe-services --region $r --output json --services $allclusterservices --cluster $c --no-paginate | jq '[.services[] | select(.launchType=="FARGATE") | select(.status=="ACTIVE")] | length')
      ACTIVE_FARGATE_SERVICES=$(($ACTIVE_FARGATE_SERVICES + $fargateactiveservices))
    fi
  done
  echo "${ACTIVE_FARGATE_SERVICES}"
}

function getLambdaFunctions {
  aws $AWS_PROFILE_STRING lambda list-functions --region $r --output json --no-paginate | jq '.Functions | length'
}

function calculateInventory {
  # profile=$1
  for r in $(getRegions); do
    if [ "$JSON" != "true" ]; then
      echo $r
    fi
    instances=$(getInstances $r)
    EC2_INSTANCES=$(($EC2_INSTANCES + $instances))

    rds=$(getRDSInstances $r)
    RDS_INSTANCES=$(($RDS_INSTANCES + $rds))

    redshift=$(getRedshift $r)
    REDSHIFT_CLUSTERS=$(($REDSHIFT_CLUSTERS + $redshift))

    elbv1=$(getElbv1 $r)
    ELB_V1=$(($ELB_V1 + $elbv1))

    elbv2=$(getElbv2 $r)
    ELB_V2=$(($ELB_V2 + $elbv2))

    natgw=$(getNatGateways $r)
    NAT_GATEWAYS=$(($NAT_GATEWAYS + $natgw))

    ecsfargateclusters=$(getECSFargateClusters $r)
    ecsfargateclusterscount=$(echo $ecsfargateclusters | wc -w)
    ECS_FARGATE_CLUSTERS=$(($ECS_FARGATE_CLUSTERS + $ecsfargateclusterscount))

    ecsfargaterunningtasks=$(getECSFargateRunningTasks $r $ecsfargateclusters)
    ECS_FARGATE_RUNNING_TASKS=$(($ECS_FARGATE_RUNNING_TASKS + $ecsfargaterunningtasks))

    ecstaskdefinitions=$(getECSTaskDefinitions $r)
    ECS_TASK_DEFINITIONS=$(($ECS_TASK_DEFINITIONS + $ecstaskdefinitions))

    ecsfargatesvcs=$(getECSFargateServices $r $ecsfargateclusters)
    ECS_FARGATE_ACTIVE_SERVICES=$(($ECS_FARGATE_ACTIVE_SERVICES + $ecsfargatesvcs))

    lambdafns=$(getLambdaFunctions $r)
    LAMBDA_FNS=$(($LAMBDA_FNS + $lambdafns))
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
  echo "Additional Serverless Inventory Details (NOT included in Total Resources count above):"
  echo "===================="
  echo "ECS Fargate Clusters:           $ECS_FARGATE_CLUSTERS"
  echo "ECS Fargate Running Tasks:      $ECS_FARGATE_RUNNING_TASKS"
  echo "ECS Fargate Active Services:    $ECS_FARGATE_ACTIVE_SERVICES"
  echo "ECS Task Definitions (all ECS): $ECS_TASK_DEFINITIONS"
  echo "Lambda Functions:               $LAMBDA_FNS"
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
  echo "  \"_ecs_fargate_running_tasks\": \"$ECS_FARGATE_RUNNING_TASKS\","
  echo "  \"_ecs_fargate_active_svcs\": \"$ECS_FARGATE_ACTIVE_SERVICES\","
  echo "  \"_ecs_task_definitions\": \"$ECS_TASK_DEFINITIONS\","
  echo "  \"_lambda_functions\": \"$LAMBDA_FNS\""
  echo "}"
}

if [ "$USE_PROFILE" == "true" ];
then
  echo "Using profiles: $AWS_PROFILE"
  for PROFILE in $(echo $AWS_PROFILE | sed "s/,/ /g")
  do
      echo "Gathering inventory for $PROFILE"

      # Use profile, use it in all AWS CLI commands
      AWS_PROFILE_STRING="--profile $PROFILE"
      calculateInventory $PROFILE
  done
else
  # No profile being used, so set an empty string to omit it from all AWS CLI commands
  AWS_PROFILE_STRING=""

  calculateInventory
fi

if [ "$JSON" == "true" ]; then
  jsonoutput
else
  textoutput
fi