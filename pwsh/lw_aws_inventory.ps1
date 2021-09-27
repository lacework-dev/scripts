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
$global:ECS_FARGATE_CLUSTERS=0
$global:ECS_FARGATE_TASKS=0
$global:ECS_FARGATE_TASK_DEFINITIONS=0
$global:ECS_FARGATE_SERVICES=0
$global:LAMBA_FNS=0

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

function getECSFargateClusters {
    param(
        $profile,
        $region 
    )
    
    $(aws --profile $profile ecs list-clusters --region $region --output json --no-paginate | ConvertFrom-Json).clusterArns
}

function getECSFargateTaskDefinitions {
    param(
        $profile,
        $region 
    )
    
    $(aws --profile $profile ecs list-task-definitions --region $region --output json --no-paginate | ConvertFrom-Json).taskDefinitionArns.Count
}

function getECSFargateTasks {
    param(
        $profile,
        $region,
        $clusters
    )
    $TASKS=0
    
    foreach ($c in $clusters){
        $clustertasks=$(aws --profile $profile ecs list-tasks --region $region --output json --cluster $c --no-paginate | ConvertFrom-Json).taskArns.Count
        $TASKS=$(($TASKS + $clustertasks))
    }
    
    $TASKS
}

function getECSFargateServices {
    param(
        $profile,
        $region,
        $clusters
    )
    $SERVICES=0
    
    foreach ($c in $clusters){
        $clusterservices=$(aws --profile $profile ecs list-services --region $region --output json --cluster $c --no-paginate | ConvertFrom-Json).serviceArns.Count
        $SERVICES=$(($SERVICES + $clusterservices))
    }
    
    $SERVICES
}

function getLambdaFunctions {
    param(
        $profile,
        $region 
    )
    
    $(aws --profile $profile lambda list-functions --region $region --output json --no-paginate | ConvertFrom-Json).Functions.Count
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
        $global:REDSHIFT_CLUSTERS=$(($global:REDSHIFT_CLUSTERS + $redshift))
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

        $ecsfargateclusters=$(getECSFargateClusters -region $r -profile $profile)
        $ecsfargateclusterscount=$ecsfargateclusters.Count
        $global:ECS_FARGATE_CLUSTERS=$(($global:ECS_FARGATE_CLUSTERS + $ecsfargateclusterscount))
        if ($v -eq $true){
            write-host "Region $r - ECS_FARGATE_CLUSTERS cluster count $ecsfargateclusterscount"
        }
        $ecsfargatetasks=$(getECSFargateTasks -region $r -profile $profile -clusters $ecsfargateclusters)
        $global:ECS_FARGATE_TASKS=$(($global:ECS_FARGATE_TASKS + $ecsfargatetasks))
        if ($v -eq $true){
            write-host "Region $r - ECS_FARGATE_TASKS task count $ecsfargatetasks"
        }
        $ecsfargatetaskdefinitions=$(getECSFargateTaskDefinitions -region $r -profile $profile)
        $global:ECS_FARGATE_TASK_DEFINITIONS=$(($global:ECS_FARGATE_TASK_DEFINITIONS + $ecsfargatetaskdefinitions))
        if ($v -eq $true){
            write-host "Region $r - ECS_FARGATE_TASK_DEFINITIONS task definition count $ecsfargatetaskdefinitions"
        }
        $ecsfargateservices=$(getECSFargateServices -region $r -profile $profile -clusters $ecsfargateclusters)
        $global:ECS_FARGATE_SERVICES=$(($global:ECS_FARGATE_SERVICES + $ecsfargateservices))
        if ($v -eq $true){
            write-host "Region $r - ECS_FARGATE_SERVICES service count $ecsfargateservices"
        }
        $lambdafns=$(getLambdaFunctions -region $r -profile $profile)
        $global:LAMBDA_FNS=$(($global:LAMBDA_FNS + $lambdafns))
        if ($v -eq $true){
            write-host "Region $r - LAMBDA_FNS function count $lambdafns"
        }
    }

    #return $global:EC2_INSTANCES + $global:RDS_INSTANCES + $global:REDSHIFT_CLUSTERS + $global:ELB_V1 + $global:ELB_V2 + $global:NAT_GATEWAYS
}

function textoutput {
  write-output  "######################################################################"
  write-output "Lacework inventory collection complete."
  write-output ""
  write-output "EC2 Instances:     $global:EC2_INSTANCES"
  write-output "RDS Instances:     $global:RDS_INSTANCES"
  write-output "Redshift Clusters: $global:REDSHIFT_CLUSTERS"
  write-output "v1 Load Balancers: $global:ELB_V1"
  write-output "v2 Load Balancers: $global:ELB_V2"
  write-output "NAT Gateways:      $global:NAT_GATEWAYS"
  write-output "===================="
  write-output "Total Resources:   $($global:EC2_INSTANCES + $global:RDS_INSTANCES + $global:REDSHIFT_CLUSTERS + $global:ELB_V1 + $global:ELB_V2 + $global:NAT_GATEWAYS)"
  write-output ""
  write-output "Additional Serverless Inventory Details (NOT included in Total Resources count above):"
  write-output "===================="
  write-output "ECS Fargate Clusters:         $global:ECS_FARGATE_CLUSTERS"
  write-output "ECS Fargate Tasks:            $global:ECS_FARGATE_TASKS"
  write-output "ECS Fargate Task Definitions: $global:ECS_FARGATE_TASK_DEFINITIONS"
  write-output "ECS Fargate Services:         $global:ECS_FARGATE_SERVICES"
  write-output "Lambda Functions:             $global:LAMBDA_FNS"
}

function jsonoutput {
  write-output "{"
  write-output  "  `"ec2`": `"$global:EC2_INSTANCES`","
  write-output  "  `"rds`": `"$global:RDS_INSTANCES`","
  write-output  "  `"redshift`": `"$global:REDSHIFT_CLUSTERS`","
  write-output  "  `"v1_lb`": `"$global:ELB_V1`","
  write-output  "  `"v2_lb`": `"$global:ELB_V2`","
  write-output  "  `"nat_gw`": `"$global:NAT_GATEWAYS`","
  write-output  "  `"total`": `"$($global:EC2_INSTANCES + $global:RDS_INSTANCES + $global:REDSHIFT_CLUSTERS + $global:ELB_V1 + $global:ELB_V2 + $global:NAT_GATEWAYS)`","
  write-output  "  `"_ecs_fargate_clusters`": `"$global:ECS_FARGATE_CLUSTERS`","
  write-output  "  `"_ecs_fargate_tasks`": `"$global:ECS_FARGATE_TASKS`","
  write-output  "  `"_ecs_fargate_task_definitions`": `"$global:ECS_FARGATE_TASK_DEFINITIONS`","
  write-output  "  `"_ecs_fargate_svcs`": `"$global:ECS_FARGATE_SERVICES`","
  write-output  "  `"_lambda_functions`": `"$global:LAMBDA_FNS`""
  write-output  "}"
}

foreach ($awsProfile in $($p.Split(",").Trim())){
    calculateInventory -profile $awsProfile
}
    
if ($json -eq $true){
    jsonoutput
}else{
    textoutput
}

