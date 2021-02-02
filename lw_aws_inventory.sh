#!/bin/bash
# Script to fetch AWS inventory for Lacework sizing.
# Requirements: awscli, jq

# You can specify a profile with the -p flag, or get JSON output with the -j flag.
# Note that the script takes a while to run in large accounts with many resources.
# the -a flag takes a list of accounts comma separated, no space (i.e "account1,account2,account3") all must have valid lines in the config file


# Usage: ./lw_aws_inventory.sh
while getopts a:p:j: opt; do
  case ${opt} in
	a )
	  IFS=', ' read -r -a accounts <<< "$OPTARG"
	  ;;
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

function getRegions {
  aws --profile $account ec2 describe-regions --output json | jq -r '.[] | .[] | .RegionName'
}

function getInstances {
  region=$1
  aws --profile $account ec2 describe-instances --query 'Reservations[*].Instances[*].[InstanceId]' --region $r --output json --no-paginate | jq 'flatten | length'
}

function getRDSInstances {
  region=$1
  aws --profile $account rds describe-db-instances --region $r --output json --no-paginate | jq '.DBInstances | length'
}

function getRedshift {
  region=$1
  aws --profile $account redshift describe-clusters --region $r --output json --no-paginate | jq '.Clusters | length'
}

function getElbv1 {
  region=$1
  aws --profile $account elb describe-load-balancers --region $r  --output json --no-paginate | jq '.LoadBalancerDescriptions | length'
}

function getElbv2 {
  region=$1
  aws --profile $account elbv2 describe-load-balancers --region $r --output json --no-paginate | jq '.LoadBalancers | length'
}

function getNatGateways {
  region=$1
  aws --profile $account ec2 describe-nat-gateways --region $r --output json --no-paginate | jq '.NatGateways | length'
}


function textoutput {
  echo "######################################################################"
  echo "Lacework inventory collection complete for $account."
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

for account in "${accounts[@]}"; do
	for r in $(getRegions $account ); do
	  if [ "$JSON" != "true" ]; then
		echo $r
	  fi
	  instances=$(getInstances $account $r)
	  EC2_INSTANCES=$(($EC2_INSTANCES + $instances))

	  rds=$(getRDSInstances $account  $r)
	  RDS_INSTANCES=$(($RDS_INSTANCES + $rds))

	  redshift=$(getRedshift $account  $r)
	  REDSHIFT_CLUSTERS=$(($REDSHIFT_CLUSTERS + $redshift))

	  elbv1=$(getElbv1 $account  $r)
	  ELB_V1=$(($ELB_V1 + $elbv1))

	  elbv2=$(getElbv2 $account  $r)
	  ELB_V2=$(($ELB_V2 + $elbv2))

	  natgw=$(getNatGateways $account  $r)
	  NAT_GATEWAYS=$(($NAT_GATEWAYS + $natgw))
	done
	echo "Finished the count for $account"
	TOTAL=$(($EC2_INSTANCES + $RDS_INSTANCES + $REDSHIFT_CLUSTERS + $ELB_V1 + $ELB_V2 + $NAT_GATEWAYS))

	if [ "$JSON" == "true" ]; then
	  jsonoutput
	else
	  textoutput
	fi
done