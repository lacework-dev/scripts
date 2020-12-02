#!/bin/bash
# Script to fetch AWS inventory for Lacework sizing.
# Requirements: awscli, jq

# You can specify a profile with the -p flag, or get JSON output with the -j flag.
# Note that the script takes a while to run in large accounts with many resources.

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

if [ "$JSON" != "true" ]; then
  if [ -z "$AWS_PROFILE" ]; then
    AWS_PROFILE=default
    echo "Running Lacework inventory against your default profile."
  else
    echo "Running Lacework inventory against profile: $AWS_PROFILE"
  fi
fi

# Set the initial counts to zero.
EC2_INSTANCES=0
RDS_INSTANCES=0
REDSHIFT_CLUSTERS=0
ELB_V1=0
ELB_V2=0
NAT_GATEWAYS=0

function getRegions {
  aws --profile $AWS_PROFILE ec2 describe-regions --output json | jq -r '.[] | .[] | .RegionName'
}

function getInstances {
  region=$1
  aws --profile $AWS_PROFILE ec2 describe-instances --query 'Reservations[*].Instances[*].[InstanceId]' --region $r --output json --no-paginate | jq 'flatten | length'
}

function getRDSInstances {
  region=$1
  aws --profile $AWS_PROFILE rds describe-db-instances --region $r --output json --no-paginate | jq '.DBInstances | length'
}

function getRedshift {
  region=$1
  aws --profile $AWS_PROFILE redshift describe-clusters --region $r --output json --no-paginate | jq '.Clusters | length'
}

function getElbv1 {
  region=$1
  aws --profile $AWS_PROFILE elb describe-load-balancers --region $r  --output json --no-paginate | jq '.LoadBalancerDescriptions | length'
}

function getElbv2 {
  region=$1
  aws --profile $AWS_PROFILE elbv2 describe-load-balancers --region $r --output json --no-paginate | jq '.LoadBalancers | length'
}

function getNatGateways {
  region=$1
  aws --profile $AWS_PROFILE ec2 describe-nat-gateways --region $r --output json --no-paginate | jq '.NatGateways | length'
}

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
done

TOTAL=$(($EC2_INSTANCES + $RDS_INSTANCES + $REDSHIFT_CLUSTERS + $ELB_V1 + $ELB_V2 + $NAT_GATEWAYS))

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
}

function jsonoutput {
  echo "{"
  echo "  \"ec2\": \"$EC2_INSTANCES\","
  echo "  \"rds\": \"$RDS_INSTANCES\","
  echo "  \"redshift\": \"$REDSHIFT_CLUSTERS\","
  echo "  \"v1_lb\": \"$ELB_V1\","
  echo "  \"v2_lb\": \"$ELB_V2\","
  echo "  \"nat_gw\": \"$NAT_GATEWAYS\","
  echo "  \"total\": \"$TOTAL\""
  echo "}"
}

if [ "$JSON" == "true" ]; then
  jsonoutput
else
  textoutput
fi