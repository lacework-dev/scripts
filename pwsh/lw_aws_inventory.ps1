# Script to fetch AWS inventory for Lacework sizing.
# Requirements: awscli

# You can specify a profile with the `-p $PROFILE_NAME` flag, or get JSON output with the `-json $true` flag.
# Note:
# 1. You can specify multiple accounts by passing a comma seperated list, e.g. "default,qa,test",
# there are no spaces between accounts in the list
# 2. The script takes a while to run in large accounts with many resources, the final count is an aggregation of all resources found.

param
(
    [CmdletBinding()]
    [bool] $json = $false,

    [CmdletBinding()]
    [string] $p = "default",

    # enable verbose output
    [CmdletBinding()]
    [bool] $v = $false
)

if (Get-Command "aws" -ErrorAction SilentlyContinue){
    $aws_installed = $true
}else{
    # setup aws-cli if not present?
    throw "aws cli must be installed and configured prior to script execution!"
}


# Set the initial counts to zero.
$global:EC2_INSTANCES=0
$global:RDS_INSTANCES=0
$global:REDSHIFT_CLUSTERS=0
$global:ELB_V1=0
$global:ELB_V2=0
$global:NAT_GATEWAYS=0

$TOTAL = 0

function getRegions {
    param(
        $profile
    )

    $(aws --profile $profile ec2 describe-regions --output json | ConvertFrom-Json).Regions.RegionName
}

function getInstances {
    param(
        $profile,
        $region 
    )

    $(aws --profile $profile ec2 describe-instances --query 'Reservations[*].Instances[*].[InstanceId]' --region $region --output json --no-paginate | ConvertFrom-Json).Count
}

function getRDSInstances {
    param(
        $profile,
        $region 
    )
    
    $(aws --profile $profile rds describe-db-instances --region $region --output json --no-paginate | ConvertFrom-Json).DBInstances.Count
}

function getRedshift {
    param(
        $profile,
        $region 
    )
    
    $(aws --profile $profile redshift describe-clusters --region $region --output json --no-paginate | ConvertFrom-Json).Clusters.Count
}

function getElbv1 {
    param(
        $profile,
        $region 
    )
    
    $(aws --profile $profile elb describe-load-balancers --region $region  --output json --no-paginate | ConvertFrom-Json).LoadBalancerDescriptions.Count
}

function getElbv2 {
    param(
        $profile,
        $region 
    )
    
    $(aws --profile $profile elbv2 describe-load-balancers --region $region --output json --no-paginate | ConvertFrom-Json).LoadBalancers.Count
}

function getNatGateways {
    param(
        $profile,
        $region 
    )
    
    $(aws --profile $profile ec2 describe-nat-gateways --region $region --output json --no-paginate | ConvertFrom-Json).NatGateways.Count
}

function calculateInventory {
    
    param(
        $profile
    )

    foreach ($r in $(getRegions -profile $profile)){
        if ($json -ne $true){
            Write-Host $r
        }

        $instances=$(getInstances -region $r -profile $profile)
        $global:EC2_INSTANCES=$(($global:EC2_INSTANCES + $instances))
        if ($v -eq $true){
            write-host "Region $r - EC2 instance count $instances"
        }

        $rds=$(getRDSInstances -region $r -profile $profile)
        $global:RDS_INSTANCES=$(($global:RDS_INSTANCES + $rds))
        if ($v -eq $true){
            write-host "Region $r - RDS instance count $rds"
        }

        $redshift=$(getRedshift -region $r -profile $profile)
        $global:REDSHIFT_CLUSTERS=$(($Rglobal:EDSHIFT_CLUSTERS + $redshift))
        if ($v -eq $true){
            write-host "Region $r - RedShift count $redshift"
        }

        $elbv1=$(getElbv1 -region $r -profile $profile)
        $global:ELB_V1=$(($global:ELB_V1 + $elbv1))
        if ($v -eq $true){
            write-host "Region $r - ELBv1 instance count $elbv1"
        }

        $elbv2=$(getElbv2 -region $r -profile $profile)
        $global:ELB_V2=$(($global:ELB_V2 + $elbv2))
        if ($v -eq $true){
            write-host "Region $r - ELBv2 instance count $elbv2"
        }

        $natgw=$(getNatGateways -region $r -profile $profile)
        $global:NAT_GATEWAYS=$(($global:NAT_GATEWAYS + $natgw))
        if ($v -eq $true){
            write-host "Region $r - NAT_GW instance count $natgw"
        }
    }

    #return $global:EC2_INSTANCES + $global:RDS_INSTANCES + $global:REDSHIFT_CLUSTERS + $global:ELB_V1 + $global:ELB_V2 + $global:NAT_GATEWAYS
}

function textoutput {
  write-host "######################################################################"
  write-host "Lacework inventory collection complete."
  write-host ""
  write-host "EC2 Instances:     $global:EC2_INSTANCES"
  write-host "RDS Instances:     $global:RDS_INSTANCES"
  write-host "Redshift Clusters: $global:REDSHIFT_CLUSTERS"
  write-host "v1 Load Balancers: $global:ELB_V1"
  write-host "v2 Load Balancers: $global:ELB_V2"
  write-host "NAT Gateways:      $global:NAT_GATEWAYS"
  write-host "===================="
  write-host "Total Resources:   $($global:EC2_INSTANCES + $global:RDS_INSTANCES + $global:REDSHIFT_CLUSTERS + $global:ELB_V1 + $global:ELB_V2 + $global:NAT_GATEWAYS)"
}

function jsonoutput {
  write-host "{"
  write-host "  `"ec2`": `"$global:EC2_INSTANCES`","
  write-host "  `"rds`": `"$global:RDS_INSTANCES`","
  write-host "  `"redshift`": `"$global:REDSHIFT_CLUSTERS`","
  write-host "  `"v1_lb`": `"$global:ELB_V1`","
  write-host "  `"v2_lb`": `"$global:ELB_V2`","
  write-host "  `"nat_gw`": `"$global:NAT_GATEWAYS`","
  write-host "  `"total`": `"$($global:EC2_INSTANCES + $global:RDS_INSTANCES + $global:REDSHIFT_CLUSTERS + $global:ELB_V1 + $global:ELB_V2 + $global:NAT_GATEWAYS)`""
  write-host "}"
}

foreach ($awsProfile in $($p.Split(",").Trim())){
    calculateInventory -profile $awsProfile
}
    
if ($json -eq $true){
    jsonoutput
}else{
    textoutput
}

