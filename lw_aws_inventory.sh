#!/bin/bash
# Script to fetch AWS inventory for Lacework sizing.
# Requirements: awscli, jq

# Usage: ./lw_aws_inventory.sh
while getopts ":p:" opt; do
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

if [ -z "$AWS_PROFILE" ]; then
  echo "Running Lacework inventory against your current profile."
else
  echo "Runnning Lacework inventory against profile: $AWS_PROFILE"
fi

# Set the initial counts to zero.
EC2_INSTANCES=0
RDS_INSTANCES=0
REDSHIFT_CLUSTERS=0
ELB_V1=0
ELB_V2=0
NAT_GATEWAYS=0

function getRegions {
  aws ec2 describe-regions --output json | jq -r '.[] | .[] | .RegionName'
}

function getInstances {
  region=$1
  aws ec2 describe-instances --filters Name=instance-state-name,Values=running --region $r --output json --no-paginate | jq '[.[] | .[] | .Instances] | length'
}

function getRDSInstances {
  region=$1
  aws rds describe-db-instances --region $r --output json --no-paginate | jq '.DBInstances | length'
}

function getRedshift {
  region=$1
  aws redshift describe-clusters --region $r --output json --no-paginate | jq '.Clusters | length'
}

function getElbv1 {
  region=$1
  aws elb describe-load-balancers --region $r  --output json --no-paginate | jq '.LoadBalancerDescriptions | length'
}

function getElbv2 {
  region=$1
  aws elbv2 describe-load-balancers --region $r --output json --no-paginate | jq '.LoadBalancers | length'
}

function getNatGateways {
  region=$1
  aws ec2 describe-nat-gateways --region $r --output json --no-paginate | jq '.NatGateways | length'
}

echo "Starting inventory check."
for r in $(getRegions); do
  echo $r
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
echo "Total Resources:   $(($EC2_INSTANCES + $RDS_INSTANCES + $REDSHIFT_CLUSTERS + $ELB_V1 + $ELB_V2 + $NAT_GATEWAYS))"
