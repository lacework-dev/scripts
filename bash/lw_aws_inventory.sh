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
ECS_CLUSTERS=0
ECS_FARGATE_RUNNING_TASKS=0
ECS_FARGATE_RUNNING_CONTAINERS=0
ECS_FARGATE_TOTAL_CONTAINERS=0
ECS_FARGATE_ACTIVE_SERVICES=0
ECS_EC2_INSTANCES=0
ECS_TASK_DEFINITIONS=0
EKS_CLUSTERS=0
EKS_NODES=0
EKS_FARGATE_ACTIVE_PROFILES=0
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

function getECSClusters {
  aws --profile $profile ecs list-clusters --region $r --output json --no-paginate | jq -r '.clusterArns[]'
}

function getECSTaskDefinitions {
  aws --profile $profile ecs list-task-definitions --region $r --output json --no-paginate | jq '.taskDefinitionArns | length'
}

function getECSFargateRunningTasks {
  RUNNING_FARGATE_TASKS=0
  for c in $ecsclusters; do
    allclustertasks=$(aws --profile $profile ecs list-tasks --region $r --output json --cluster $c --no-paginate | jq -r '.taskArns | join(" ")')
    if [ -n "${allclustertasks}" ]; then
      fargaterunningtasks=$(aws --profile $profile ecs describe-tasks --region $r --output json --tasks $allclustertasks --cluster $c --no-paginate | jq '[.tasks[] | select(.launchType=="FARGATE") | select(.lastStatus=="RUNNING")] | length')
      RUNNING_FARGATE_TASKS=$(($RUNNING_FARGATE_TASKS + $fargaterunningtasks))
    fi
  done

  echo "${RUNNING_FARGATE_TASKS}"
}

function getECSFargateRunningContainers {
  RUNNING_FARGATE_CONTAINERS=0
  for c in $ecsclusters; do
    allclustertasks=$(aws --profile $profile ecs list-tasks --region $r --output json --cluster $c --no-paginate | jq -r '.taskArns | join(" ")')
    if [ -n "${allclustertasks}" ]; then
      fargaterunningcontainers=$(aws --profile $profile ecs describe-tasks --region $r --output json --tasks $allclustertasks --cluster $c --no-paginate | jq '[.tasks[] | select(.launchType=="FARGATE") | select(.lastStatus=="RUNNING") | .containers[] | select(.lastStatus=="RUNNING")] | length')
      RUNNING_FARGATE_CONTAINERS=$(($RUNNING_FARGATE_CONTAINERS + $fargaterunningcontainers))
    fi
  done

  echo "${RUNNING_FARGATE_CONTAINERS}"
}

function getECSFargateTotalContainers {
  TOTAL_FARGATE_CONTAINERS=0
  for c in $ecsclusters; do
    allclustertasks=$(aws --profile $profile ecs list-tasks --region $r --output json --cluster $c --no-paginate | jq -r '.taskArns | join(" ")')
    if [ -n "${allclustertasks}" ]; then
      fargatetotalcontainers=$(aws --profile $profile ecs describe-tasks --region $r --output json --tasks $allclustertasks --cluster $c --no-paginate | jq '[.tasks[] | select(.launchType=="FARGATE") | select(.lastStatus=="RUNNING") | .containers[] ] | length')
      TOTAL_FARGATE_CONTAINERS=$(($TOTAL_FARGATE_CONTAINERS + $fargatetotalcontainers))
    fi
  done

  echo "${TOTAL_FARGATE_CONTAINERS}"
}

function getECSFargateServices {
  ACTIVE_FARGATE_SERVICES=0
  for c in $ecsclusters; do
    allclusterservices=$(aws --profile $profile ecs list-services --region $r --output json --cluster $c --no-paginate | jq -r '.serviceArns | join(" ")')
    if [ -n "${allclusterservices}" ]; then
      fargateactiveservices=$(aws --profile $profile ecs describe-services --region $r --output json --services $allclusterservices --cluster $c --no-paginate | jq '[.services[] | select(.launchType=="FARGATE") | select(.status=="ACTIVE")] | length')
      ACTIVE_FARGATE_SERVICES=$(($ACTIVE_FARGATE_SERVICES + $fargateactiveservices))
    fi
  done
  echo "${ACTIVE_FARGATE_SERVICES}"
}

function getECSEC2Instances {
  ECS_EC2_INSTANCES=0
  for c in $ecsclusters; do
    ecsec2instances=$(aws --profile $profile ecs list-container-instances --region $r --cluster $c | jq '.containerInstanceArns | length')
    ECS_EC2_INSTANCES=$(($ECS_EC2_INSTANCES + $ecsec2instances))
  done
  echo "${ECS_EC2_INSTANCES}"
}

function getEKSClusters {
  EKS_CLUSTERS=$(aws --profile $profile eks list-clusters --region $r --output json --no-paginate | jq -r '.clusters | .[]')
  echo "${EKS_CLUSTERS}"
}

function getEKSNodes {
  EKS_NODES=0
  for c in $eksclusters; do
    eksnodegroups=$(aws --profile $profile eks list-nodegroups --cluster-name $c --region $r | jq -r '.nodegroups | .[]')
    for ng in $eksnodegroups; do
      asgroups=$(aws --profile $profile eks describe-nodegroup --cluster-name $c --region $r --nodegroup-name $ng | jq -r '.nodegroup | .resources | .autoScalingGroups[] | .name')
      for asg in $asgroups; do
        eksnodes=$(aws --profile $profile autoscaling describe-auto-scaling-groups --auto-scaling-group-names $asg --region $r | jq '.AutoScalingGroups[] | .Instances | length')
        EKS_NODES=$(($EKS_NODES + $eksnodes))
      done
    done
  done
  echo "${EKS_NODES}"
}

function getEKSFargateActiveProfiles {
  EKS_FARGATE_ACTIVE_PROFILES=0
  for c in $eksclusters; do
    eksfargateprofiles=$(aws eks list-fargate-profiles --profile $profile --region $r --cluster-name $c | jq -r '.fargateProfileNames[]')
    for p in $eksfargateprofiles; do
      activeprofiles=$(aws eks describe-fargate-profile --profile $profile --region $r --cluster-name $c --fargate-profile-name $p | jq ' [.fargateProfile | select(.status=="ACTIVE")] | length')
      EKS_FARGATE_ACTIVE_PROFILES=$(($EKS_FARGATE_ACTIVE_PROFILES + $activeprofiles))
    done
  done
  echo "${EKS_FARGATE_ACTIVE_PROFILES}"
}

function getLambdaFunctions {
  aws --profile $profile lambda list-functions --region $r --output json --no-paginate | jq '.Functions | length'
}

function calculateInventory {
  profile=$1
  for r in $(getRegions); do
    if [ "$JSON" != "true" ]; then
      echo "Scanning $r..."
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

    ecsclusters=$(getECSClusters $r $profile)
    ecsclusterscount=$(echo $ecsclusters | wc -w)
    ECS_CLUSTERS=$(($ECS_CLUSTERS + $ecsclusterscount))

    ecsfargaterunningtasks=$(getECSFargateRunningTasks $r $ecsclusters $profile)
    ECS_FARGATE_RUNNING_TASKS=$(($ECS_FARGATE_RUNNING_TASKS + $ecsfargaterunningtasks))

    ecsfargaterunningcontainers=$(getECSFargateRunningContainers $r $ecsclusters $profile)
    ECS_FARGATE_RUNNING_CONTAINERS=$(($ECS_FARGATE_RUNNING_CONTAINERS + $ecsfargaterunningcontainers))

    ecsfargatetotalcontainers=$(getECSFargateTotalContainers $r $ecsclusters $profile)
    ECS_FARGATE_TOTAL_CONTAINERS=$(($ECS_FARGATE_TOTAL_CONTAINERS + $ecsfargatetotalcontainers))

    ecsec2instances=$(getECSEC2Instances $r $ecsclusters $profile)
    ECS_EC2_INSTANCES=$(($ECS_EC2_INSTANCES + $ecsec2instances))

    ecstaskdefinitions=$(getECSTaskDefinitions $r $profile)
    ECS_TASK_DEFINITIONS=$(($ECS_TASK_DEFINITIONS + $ecstaskdefinitions))

    ecsfargatesvcs=$(getECSFargateServices $r $ecsclusters $profile)
    ECS_FARGATE_ACTIVE_SERVICES=$(($ECS_FARGATE_ACTIVE_SERVICES + $ecsfargatesvcs))

    eksclusters=$(getEKSClusters $r $profile)
    eksclusterscount=$(echo $eksclusters | wc -w)
    EKS_CLUSTERS=$(($EKS_CLUSTERS + $eksclusterscount))

    eksnodes=$(getEKSNodes $r $eksclusters $profile)
    EKS_NODES=$(($EKS_NODES + $eksnodes))

    eksfargateactiveprofiles=$(getEKSFargateActiveProfiles $r $eksclusters $profile)
    EKS_FARGATE_ACTIVE_PROFILES=$(($EKS_FARGATE_ACTIVE_PROFILES + $eksfargateactiveprofiles))

    lambdafns=$(getLambdaFunctions $r $profile)
    LAMBDA_FNS=$(($LAMBDA_FNS + $lambdafns))

done
TOTAL=$(($EC2_INSTANCES + $RDS_INSTANCES + $REDSHIFT_CLUSTERS + $ELB_V1 + $ELB_V2 + $NAT_GATEWAYS))
TOTAL_CONTAINERIZED_EC2S=$(($ECS_EC2_INSTANCES + $EKS_NODES))
}

function textoutput {
  echo "######################################################################"
  echo "Cloud Resource Inventory"
  echo "------------------"
  echo "EC2 Instances:			$EC2_INSTANCES"
  echo "RDS Instances:			$RDS_INSTANCES"
  echo "Redshift Clusters:		$REDSHIFT_CLUSTERS"
  echo "v1 Load Balancers:		$ELB_V1"
  echo "v2 Load Balancers:		$ELB_V2"
  echo "NAT Gateways:			$NAT_GATEWAYS"
  echo "------------------"
  echo "Total Cloud Resources:		$TOTAL"
  echo ""
  echo ""
  echo "Workload Inventory"
  echo "------------------"
  echo "ECS Clusters:			$ECS_CLUSTERS"
  echo "ECS Task Definitions:		$ECS_TASK_DEFINITIONS"
  echo "ECS Fargate Running Tasks:      $ECS_FARGATE_RUNNING_TASKS"
  echo "ECS Fargate Running Containers: $ECS_FARGATE_RUNNING_CONTAINERS"
  echo "ECS Fargate Total Containers:   $ECS_FARGATE_TOTAL_CONTAINERS"
  echo "ECS Fargate Active Services:    $ECS_FARGATE_ACTIVE_SERVICES"
  echo "ECS EC2 Instances:		$ECS_EC2_INSTANCES"
  echo "EKS Clusters:			$EKS_CLUSTERS"
  echo "EKS Fargate Active Profiles:	$EKS_FARGATE_ACTIVE_PROFILES"
  echo "EKS EC2 Nodes:			$EKS_NODES"
  echo "Lambda Functions:               $LAMBDA_FNS"
  echo "------------------"
  echo "Total Containerized EC2s:	$TOTAL_CONTAINERIZED_EC2S"
  echo "######################################################################"
}

function jsonoutput {
  echo "{"
  echo "  \"ec2\": \"$EC2_INSTANCES\","
  echo "  \"rds\": \"$RDS_INSTANCES\","
  echo "  \"redshift\": \"$REDSHIFT_CLUSTERS\","
  echo "  \"v1_lb\": \"$ELB_V1\","
  echo "  \"v2_lb\": \"$ELB_V2\","
  echo "  \"nat_gw\": \"$NAT_GATEWAYS\","
  echo "  \"total_resources\": \"$TOTAL\","
  echo "  \"ecs_clusters\": \"$ECS_CLUSTERS\","
  echo "  \"ecs_task_definitions\": \"$ECS_TASK_DEFINITIONS\","
  echo "  \"ecs_fargate_running_tasks\": \"$ECS_FARGATE_RUNNING_TASKS\","
  echo "  \"ecs_fargate_running_containers\": \"$ECS_FARGATE_RUNNING_CONTAINERS\","
  echo "  \"ecs_fargate_total_containers\": \"$ECS_FARGATE_TOTAL_CONTAINERS\","
  echo "  \"ecs_fargate_active_svcs\": \"$ECS_FARGATE_ACTIVE_SERVICES\","
  echo "  \"ecs_ec2_instances\": \"$ECS_EC2_INSTANCES\","
  echo "  \"eks_clusters\": \"$EKS_CLUSTERS\","
  echo "  \"eks_fargate_active_profiles\": \"$EKS_FARGATE_ACTIVE_PROFILES\","
  echo "  \"eks_ec2_nodes\": \"$EKS_NODES\","
  echo "  \"lambda_functions\": \"$LAMBDA_FNS\""
  echo "  \"total_containerized_ec2s\": \"$TOTAL_CONTAINERIZED_EC2S\","
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
