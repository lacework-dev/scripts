#!/bin/bash
# Script to fetch AWS inventory for Lacework sizing.
# Requirements: awscli, jq

# You can specify a profile with the -p flag, or get JSON output with the -j flag.
# Note:
# 1. You can specify multiple accounts by passing a comma seperated list, e.g. "default,qa,test",
# there are no spaces between accounts in the list
# 2. The script takes a while to run in large accounts with many resources, the final count is an aggregation of all resources found.


AWS_PROFILE=default

# Usage: ./lw_aws_inventory.sh
while getopts ":jp:" opt; do
  case ${opt} in
    p )
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
ECS_FARGATE_TASKS=0
ECS_FARGATE_TASK_DEFINITIONS=0
ECS_FARGATE_SERVICES=0
LAMBDA_FNS=0

function getRegions {
  aws --profile $profile ec2 describe-regions --output json | jq -r '.[] | .[] | .RegionName'
}

function getInstances {
  aws --profile $profile ec2 describe-instances --query 'Reservations[*].Instances[*].[InstanceId]' --region $r --output json --no-paginate | jq 'flatten | length'
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

function getECSFargateTaskDefinitions {
  aws --profile $profile ecs list-task-definitions --region $r --output json --no-paginate | jq -r '.taskDefinitionArns | length'
}

function getECSFargateTasks {
  TASKS=0
  for c in $ecsfargateclusters; do
    clustertasks=$(aws --profile $profile ecs list-tasks --region $r --output json --cluster $c --no-paginate | jq '.taskArns | length')
    TASKS=$(($TASKS + $clustertasks))
  done
  echo "${TASKS}"
}

function getECSFargateServices {
  SERVICES=0
  for c in $ecsfargateclusters; do
    clusterservices=$(aws --profile $profile ecs list-services --region $r --output json --cluster $c --no-paginate | jq '.serviceArns | length')
    SERVICES=$(($SERVICES + $clusterservices))
  done
  echo "${SERVICES}"
}

function getLambdaFunctions {
  aws --profile $profile lambda list-functions --region $r --output json --no-paginate | jq '.NatGateways | length'
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

    ecsfargatetasks=$(getECSFargateTasks $r $ecsfargateclusters $profile)
    ECS_FARGATE_TASKS=$(($ECS_FARGATE_TASKS + $ecsfargatetasks))

    ecsfargatetaskdefinitions=$(getECSFargateTaskDefinitions $r $profile)
    ECS_FARGATE_TASK_DEFINITIONS=$(($ECS_FARGATE_TASK_DEFINITIONS + $ecsfargatetaskdefinitions))

    ecsfargatesvcs=$(getECSFargateServices $r $ecsfargateclusters $profile)
    ECS_FARGATE_SERVICES=$(($ECS_FARGATE_SERVICES + $ecsfargatesvcs))

    lambdafns=$(getLambdaFunctions $r $profile)
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
  echo "Additional Serverless Inventory Details:"
  echo "===================="
  echo "ECS Fargate Clusters:         $ECS_FARGATE_CLUSTERS"
  echo "ECS Fargate Tasks:            $ECS_FARGATE_TASKS"
  echo "ECS Fargate Task Definitions: $ECS_FARGATE_TASK_DEFINITIONS"
  echo "ECS Fargate Services:         $ECS_FARGATE_SERVICES"
  echo "Lambda Functions:             $LAMBDA_FNS"
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
  echo "  \"_ecs_fargate_tasks\": \"$ECS_FARGATE_TASKS\","
  echo "  \"_ecs_fargate_task_definitions\": \"$ECS_FARGATE_TASK_DEFINITIONS\","
  echo "  \"_ecs_fargate_svcs\": \"$ECS_FARGATE_SERVICES\","
  echo "  \"_lambda_functions\": \"$LAMBDA_FNS\""
  echo "}"
}

for PROFILE in $(echo $AWS_PROFILE | sed "s/,/ /g")
do
    calculateInventory $PROFILE
done

if [ "$JSON" == "true" ]; then
  jsonoutput
else
  textoutput
fi
