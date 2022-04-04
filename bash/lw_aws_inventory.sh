#!/bin/bash
# Script to fetch AWS inventory for Lacework sizing.
# Requirements: awscli, jq

# You can specify a profile with the -p flag
# Note:
# 1. You can specify multiple accounts by passing a comma seperated list, e.g. "default,qa,test",
# there are no spaces between accounts in the list
# 2. The script takes a while to run in large accounts with many resources, provides details per account and a final summary of all resources found.


AWS_PROFILE=default
export AWS_MAX_ATTEMPTS=20

# Usage: ./lw_aws_inventory.sh
while getopts ":jp::t" opt; do
  case ${opt} in
    p )
      AWS_PROFILE=$OPTARG
      ;;
    \? )
      echo "Usage: ./lw_aws_inventory.sh [-p profile]" 1>&2
      exit 1
      ;;
    : )
      echo "Usage: ./lw_aws_inventory.sh [-p profile]" 1>&2
      exit 1
      ;;
  esac
done
shift $((OPTIND -1))

# Set the initial counts to zero.
ACCOUNTS=0
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

function getAccountId {
  aws --profile $profile sts get-caller-identity --query "Account" --output text
}

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
  accountid=$(getAccountId $profile)

  accountEC2Instances=0
  accountRDSInstances=0
  accountRedshiftClusters=0
  accountELBV1=0
  accountELBV2=0
  accountNATGateways=0
  accountECSFargateClusters=0
  accountECSFargateRunningTasks=0
  accountLambdaFunctions=0

  printf "$profile, $accountid, "
  for r in $(getRegions); do
    printf "$r "

    instances=$(getInstances $r $profile)
    EC2_INSTANCES=$(($EC2_INSTANCES + $instances))
    accountEC2Instances=$(($accountEC2Instances + $instances))

    rds=$(getRDSInstances $r $profile)
    RDS_INSTANCES=$(($RDS_INSTANCES + $rds))
    accountRDSInstances=$(($accountRDSInstances + $rds))

    redshift=$(getRedshift $r $profile)
    REDSHIFT_CLUSTERS=$(($REDSHIFT_CLUSTERS + $redshift))
    accountRedshiftClusters=$(($accountRedshiftClusters + $redshift))

    elbv1=$(getElbv1 $r $profile)
    ELB_V1=$(($ELB_V1 + $elbv1))
    accountELBV1=$(($accountELBV1 + $elbv1))

    elbv2=$(getElbv2 $r $profile)
    ELB_V2=$(($ELB_V2 + $elbv2))
    accountELBV2=$(($accountELBV2 + $elbv2))

    natgw=$(getNatGateways $r $profile)
    NAT_GATEWAYS=$(($NAT_GATEWAYS + $natgw))
    accountNATGateways=$(($accountNATGateways + $natgw))

    ecsfargateclusters=$(getECSFargateClusters $r $profile)
    ecsfargateclusterscount=$(echo $ecsfargateclusters | wc -w | xargs)
    ECS_FARGATE_CLUSTERS=$(($ECS_FARGATE_CLUSTERS + $ecsfargateclusterscount))
    accountECSFargateClusters=$(($ECS_FARGATE_CLUSTERS + $ecsfargateclusterscount))

    ecsfargaterunningtasks=$(getECSFargateRunningTasks $r $ecsfargateclusters $profile)
    ECS_FARGATE_RUNNING_TASKS=$(($ECS_FARGATE_RUNNING_TASKS + $ecsfargaterunningtasks))
    accountECSFargateRunningTasks=$(($ECS_FARGATE_RUNNING_TASKS + $ecsfargaterunningtasks))

    lambdafns=$(getLambdaFunctions $r $profile)
    LAMBDA_FNS=$(($LAMBDA_FNS + $lambdafns))
    accountLambdaFunctions=$(($LAMBDA_FNS + $lambdafns))
    if [ $LAMBDA_FNS -gt 0 ]; then LAMBDA_FNS_EXIST="Yes"; fi 

    regiontotal=$(($instances + $rds + $redshift + $elbv1 + $elbv2 + $natgw))

  done
  accountTotal=$(($accountEC2Instances + $accountRDSInstances + $accountRedshiftClusters + $accountELBV1 + $accountELBV2 + $accountNATGateways))

  echo , "$accountEC2Instances", "$accountRDSInstances", "$accountRedshiftClusters", "$accountELBV1", "$accountELBV2", "$accountNATGateways", "$accountTotal", "$accountECSFargateClusters", "$accountECSFargateRunningTasks", "$accountLambdaFunctions"

  TOTAL=$(($EC2_INSTANCES + $RDS_INSTANCES + $REDSHIFT_CLUSTERS + $ELB_V1 + $ELB_V2 + $NAT_GATEWAYS))
}

function textoutput {
  echo "######################################################################"
  echo "Lacework inventory collection complete."
  echo ""
  echo "Accounts Analyzed: $ACCOUNTS"
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

echo "Profile", "Account ID", "Regions", "EC2 Instances", "RDS Instances", "Redshift Clusters", "v1 Load Balancers", "v2 Load Balancers", "NAT Gateways", "Total Resources", "ECS Fargate Clusters", "ECS Fargate Running Containers/Tasks", "Lambda Functions"

for PROFILE in $(echo $AWS_PROFILE | sed "s/,/ /g")
do
    ACCOUNTS=$(($ACCOUNTS + 1))
    calculateInventory $PROFILE
done

textoutput
