# Script to fetch AWS inventory for Lacework sizing.
# Requirements: awscli

# You can specify a profile with the -p flag, or get JSON output with the -j flag.
# Note:
# 1. You can specify multiple accounts by passing a comma seperated list, e.g. "default,qa,test",
# there are no spaces between accounts in the list
# 2. The script takes a while to run in large accounts with many resources, the final count is an aggregation of all resources found.

param
(
    [CmdletBinding()]
    [bool] $j = $false,

    [CmdletBinding()]
    [string] $p = "default"
)

$AWS_PROFILE=$p

<#
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
#>

# Set the initial counts to zero.
$EC2_INSTANCES=0
$RDS_INSTANCES=0
$REDSHIFT_CLUSTERS=0
$ELB_V1=0
$ELB_V2=0
$NAT_GATEWAYS=0

$TOTAL = 0

function getRegions {
  $(aws --profile $profile ec2 describe-regions --output json | ConvertFrom-Json).Regions.RegionName
}

function getInstances {
  $(aws --profile $profile ec2 describe-instances --query 'Reservations[*].Instances[*].[InstanceId]' --region $r --output json --no-paginate | ConvertFrom-Json).Count
}

function getRDSInstances {
  $(aws --profile $profile rds describe-db-instances --region $r --output json --no-paginate | ConvertFrom-Json).DBInstances.Count
}

function getRedshift {
  $(aws --profile $profile redshift describe-clusters --region $r --output json --no-paginate | ConvertFrom-Json).Clusters.Count
}

function getElbv1 {
  $(aws --profile $profile elb describe-load-balancers --region $r  --output json --no-paginate | ConvertFrom-Json).LoadBalancerDescriptions.Count
}

function getElbv2 {
  $(aws --profile $profile elbv2 describe-load-balancers --region $r --output json --no-paginate | ConvertFrom-Json).LoadBalancers.Count
}

function getNatGateways {
  $(aws --profile $profile ec2 describe-nat-gateways --region $r --output json --no-paginate | ConvertFrom-Json).NatGateways.Count
}

function calculateInventory {
    
    param(
        $profile
    )

    foreach ($r in $(getRegions)){
        if ($JSON -ne $true){
            Write-Host $r
        }
        $instances=$(getInstances $r $profile)
        $EC2_INSTANCES=$(($EC2_INSTANCES + $instances))

        $rds=$(getRDSInstances $r $profile)
        $RDS_INSTANCES=$(($RDS_INSTANCES + $rds))

        $redshift=$(getRedshift $r $profile)
        $REDSHIFT_CLUSTERS=$(($REDSHIFT_CLUSTERS + $redshift))

        $elbv1=$(getElbv1 $r $profile)
        $ELB_V1=$(($ELB_V1 + $elbv1))

        $elbv2=$(getElbv2 $r $profile)
        $ELB_V2=$(($ELB_V2 + $elbv2))

        $natgw=$(getNatGateways $r $profile)
        $NAT_GATEWAYS=$(($NAT_GATEWAYS + $natgw))
    }
    
    return $EC2_INSTANCES + $RDS_INSTANCES + $REDSHIFT_CLUSTERS + $ELB_V1 + $ELB_V2 + $NAT_GATEWAYS
}

function textoutput {
  write-host "######################################################################"
  write-host "Lacework inventory collection complete."
  write-host ""
  write-host "EC2 Instances:     $EC2_INSTANCES"
  write-host "RDS Instances:     $RDS_INSTANCES"
  write-host "Redshift Clusters: $REDSHIFT_CLUSTERS"
  write-host "v1 Load Balancers: $ELB_V1"
  write-host "v2 Load Balancers: $ELB_V2"
  write-host "NAT Gateways:      $NAT_GATEWAYS"
  write-host "===================="
  write-host "Total Resources:   $TOTAL"
}

function jsonoutput {
  write-host "{"
  write-host "  \"ec2\": \"$EC2_INSTANCES\","
  write-host "  \"rds\": \"$RDS_INSTANCES\","
  write-host "  \"redshift\": \"$REDSHIFT_CLUSTERS\","
  write-host "  \"v1_lb\": \"$ELB_V1\","
  write-host "  \"v2_lb\": \"$ELB_V2\","
  write-host "  \"nat_gw\": \"$NAT_GATEWAYS\","
  write-host "  \"total\": \"$TOTAL\""
  write-host "}"
}

# TOOD: figure out if we support this? 
#foreach ($PROFILE in $(echo $AWS_PROFILE | sed "s/,/ /g")){
$TOTAL = calculateInventory -profile $PROFILE
#}
    
if ($JSON -eq $true){
    write-host $jsonoutput
}else{
    write-host $textoutput
}

