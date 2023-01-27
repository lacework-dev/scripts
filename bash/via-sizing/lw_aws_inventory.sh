#!/bin/bash
# Script to fetch AWS inventory for Lacework sizing.
# Requirements: awscli, jq

# You can specify a profile with the -p flag and to scan an AWS organization using the -o flag
# Note:
# 1. You can specify multiple accounts by passing a comma seperated list, e.g. "default,qa,test",
# there are no spaces between accounts in the list
# 2. It's possible to specify a comma separated list of regions to scan to speed up the scan.
# 2. In order to scan a whole AWS organiation, the scripts assumes the presence of a OrganizationAccountAccessRole
# role in each account to perform the scan.
# 3. The script takes a while to run in large accounts with many resources, provides details per 
# account and a final summary of all resources found.


AWS_PROFILE=""
SCAN_ORGANIZATION=FALSE
export AWS_MAX_ATTEMPTS=20
REGIONS=""

ORG_AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
ORG_AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
ORG_AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN

# Usage: ./lw_aws_inventory.sh
while getopts ":p:or:" opt; do
  case ${opt} in
    p )
      AWS_PROFILE=$OPTARG
      ;;
    o )
      SCAN_ORGANIZATION=TRUE
      ;;
    r )
      REGIONS=$(echo $OPTARG | sed "s/,/ /g")
      ;;
    \? )
      echo "Usage: ./lw_aws_inventory.sh [-p profile] [-o] [-r regions]" 1>&2
      exit 1
      ;;
    : )
      echo "Usage: ./lw_aws_inventory.sh [-p profile] [-o] [-r regions]" 1>&2
      exit 1
      ;;
  esac
done
shift $((OPTIND -1))

# Set the initial counts to zero.
ACCOUNTS=0
ORGANIZATIONS=0
EC2_INSTANCES=0
EC2_INSTANCE_VCPU=0
ECS_FARGATE_CLUSTERS=0
ECS_FARGATE_RUNNING_TASKS=0
ECS_FARGATE_CPUS=0
LAMBDA_FUNCTIONS=0
LAMBDA_MEMORY_TOTAL=0


function getAccountId {
  aws $profile_string sts get-caller-identity --query "Account" --output text
}

function getRegions {
  aws $profile_string ec2 describe-regions --output json | jq -r '.[] | .[] | .RegionName'
}

function getEC2Instances {
  aws $profile_string ec2 describe-instances --query 'Reservations[*].Instances[*].[InstanceId]' --filters Name=instance-state-name,Values=running,stopped --region $r --output json --no-paginate | jq 'flatten | length'
}

function getEC2InstacevCPUs {
  cpucounts=$(aws $profile_string ec2 describe-instances --query 'Reservations[*].Instances[*].[CpuOptions]' --filters Name=instance-state-name,Values=running,stopped --region $r --output json --no-paginate | jq  '.[] | .[] | .[] | .CoreCount * .ThreadsPerCore')
  returncount=0
  for cpucount in $cpucounts; do
    returncount=$(($returncount + $cpucount))
  done
  echo "${returncount}"
}

function getECSFargateClusters {
  aws $profile_string ecs list-clusters --region $r --output json --no-paginate | jq -r '.clusterArns[]'
}

function getECSFargateRunningTasks {
  RUNNING_FARGATE_TASKS=0
  for c in $ecsfargateclusters; do
    allclustertasks=$(aws $profile_string ecs list-tasks --region $r --output json --cluster $c --no-paginate | jq -r '.taskArns | join(" ")')
    if [ -n "${allclustertasks}" ]; then
      fargaterunningtasks=$(aws $profile_string ecs describe-tasks --region $r --output json --tasks $allclustertasks --cluster $c --no-paginate | jq '[.tasks[] | select(.launchType=="FARGATE") | select(.lastStatus=="RUNNING")] | length')
      RUNNING_FARGATE_TASKS=$(($RUNNING_FARGATE_TASKS + $fargaterunningtasks))
    fi
  done

  echo "${RUNNING_FARGATE_TASKS}"
}

function getECSFargateRunningCPUs {
  RUNNING_FARGATE_CPUS=0
  for c in $ecsfargateclusters; do
    allclustertasks=$(aws $profile_string ecs list-tasks --region $r --output json --cluster $c --no-paginate | jq -r '.taskArns | join(" ")')
    if [ -n "${allclustertasks}" ]; then
      cpucounts=$(aws $profile_string ecs describe-tasks --region $r --output json --tasks $allclustertasks --cluster $c --no-paginate | jq '[.tasks[] | select(.launchType=="FARGATE") | select(.lastStatus=="RUNNING")] | .[].cpu | tonumber')

      for cpucount in $cpucounts; do
        RUNNING_FARGATE_CPUS=$(($RUNNING_FARGATE_CPUS + $cpucount))
      done
    fi
  done

  echo "${RUNNING_FARGATE_CPUS}"
}

function getLambdaFunctions {
  aws $profile_string lambda list-functions --region $r --output json --no-paginate | jq '.Functions | length'
}

function getLambdaFunctionMemory {
  memoryForAllFunctions=$(aws $profile_string lambda list-functions --region $r --output json --no-paginate | jq '.Functions[].MemorySize')
  TOTAL_LAMBDA_MEMORY=0
  for memory in $memoryForAllFunctions; do
    TOTAL_LAMBDA_MEMORY=$(($TOTAL_LAMBDA_MEMORY + $memory))
  done
  
  echo "${TOTAL_LAMBDA_MEMORY}"
}

function calculateInventory {
  account_name=$1
  profile_string=$2
  accountid=$(getAccountId "profile_string")
  accountEC2Instances=0
  accountEC2vCPUs=0
  accountECSFargateClusters=0
  accountECSFargateRunningTasks=0
  accountECSFargateCPUs=0
  accountLambdaFunctions=0
  accountLambdaMemory=0
  accountTotalvCPUs=0

  printf "$account_name, $accountid,"
  local regionsToScan=$REGIONS
  if [ -z "$regionsToScan" ]
  then
      # Regions to scan not set, get list from AWS
      regionsToScan=$(getRegions)
  fi

  for r in $regionsToScan; do
    printf " $r"

    instances=$(getEC2Instances $r $profile_string)
    EC2_INSTANCES=$(($EC2_INSTANCES + $instances))
    accountEC2Instances=$(($accountEC2Instances + $instances))

    ec2vcpu=$(getEC2InstacevCPUs $r $profile_string)
    EC2_INSTANCE_VCPU=$(($EC2_INSTANCE_VCPU + $ec2vcpu))
    accountEC2vCPUs=$(($accountEC2vCPUs + $ec2vcpu))

    ecsfargateclusters=$(getECSFargateClusters $r $profile_string)
    ecsfargateclusterscount=$(echo $ecsfargateclusters | wc -w | xargs)
    ECS_FARGATE_CLUSTERS=$(($ECS_FARGATE_CLUSTERS + $ecsfargateclusterscount))
    accountECSFargateClusters=$(($accountECSFargateClusters + $ecsfargateclusterscount))

    ecsfargaterunningtasks=$(getECSFargateRunningTasks $r $ecsfargateclusters $profile_string)
    ECS_FARGATE_RUNNING_TASKS=$(($ECS_FARGATE_RUNNING_TASKS + $ecsfargaterunningtasks))
    accountECSFargateRunningTasks=$(($accountECSFargateRunningTasks + $ecsfargaterunningtasks))

    ecsfargatecpu=$(getECSFargateRunningCPUs $r $profile_string)
    ECS_FARGATE_CPUS=$(($ECS_FARGATE_CPUS + $ecsfargatecpu))
    accountECSFargateCPUs=$(($accountECSFargateCPUs + $ecsfargatecpu))

    lambdafunctions=$(getLambdaFunctions $r $profile_string)
    LAMBDA_FUNCTIONS=$(($LAMBDA_FUNCTIONS + $lambdafunctions))
    accountLambdaFunctions=$(($accountLambdaFunctions + $lambdafunctions))

    lambdamemory=$(getLambdaFunctionMemory $r $profile_string)
    LAMBDA_MEMORY_TOTAL=$(($LAMBDA_MEMORY_TOTAL + $lambdamemory))
    accountLambdaMemory=$(($accountLambdaMemory + $lambdamemory))
  done

  accountECSFargatevCPUs=$(($accountECSFargateCPUs / 1024))
  accountLambdavCPUs=$(($accountLambdaMemory / 1024))
  accountTotalvCPUs=$(($accountEC2vCPUs + $accountECSFargatevCPUs + $accountLambdavCPUs))

  echo , "$accountEC2Instances", "$accountEC2vCPUs", "$accountECSFargateClusters", "$accountECSFargateRunningTasks", "$accountECSFargateCPUs", "$accountECSFargatevCPUs", "$accountLambdaFunctions", "$accountLambdaMemory", "$accountLambdavCPUs", "$accountTotalvCPUs"
}

function textoutput {
  echo "######################################################################"
  echo "Lacework inventory collection complete."
  echo ""
  echo "Organizations Analyzed: $ORGANIZATIONS"
  echo "Accounts Analyzed:      $ACCOUNTS"
  echo ""
  echo "EC2 Information"
  echo "===================="
  echo "EC2 Instances:     $EC2_INSTANCES"
  echo "EC2 vCPUs:         $EC2_INSTANCE_VCPU"
  echo ""
  echo "Fargate Information"
  echo "===================="
  echo "ECS Fargate Clusters:            $ECS_FARGATE_CLUSTERS"
  echo "ECS Fargate Running Tasks:       $ECS_FARGATE_RUNNING_TASKS"
  echo "ECS Fargate Container CPU Units: $ECS_FARGATE_CPUS"
  echo "ECS Fargate vCPUs:               $ECS_FARGATE_VCPUS"
  echo ""
  echo "Lambda Information"
  echo "===================="
  echo "Lambda Functions:     $LAMBDA_FUNCTIONS"
  echo "MB Lambda Memory:     $LAMBDA_MEMORY_TOTAL"
  echo "Lambda License vCPUs: $LAMBDA_VCPUS"
  echo ""
  echo "License Summary"
  echo "===================="
  echo "Total vCPUs:       $TOTAL_VCPUS"
}

echo "Profile", "Account ID", "Regions", "EC2 Instances", "EC2 vCPUs", "ECS Fargate Clusters", "ECS Fargate Running Containers/Tasks", "ECS Fargate CPU Units", "ECS Fargate License vCPUs", "Lambda Functions", "MB Lambda Memory", "Lambda License vCPUs", "Total vCPUSs"


function doAnalyzeOrganization {
    local profile_string=$1
    local accounts=$(aws $profile_string organizations list-accounts | jq -c '.Accounts[]' | jq -c '{Id, Name}')
    for account in $(echo $accounts | jq -r '.Id')
    do
        ACCOUNTS=$(($ACCOUNTS + 1))
        local account_name=$(echo $accounts | jq -c | grep $account | jq -r '.Name')
        local account_credentials=$(aws $profile_string sts assume-role --role-session-name LW-INVENTORY --role-arn arn:aws:iam::$account:role/OrganizationAccountAccessRole)

        export AWS_ACCESS_KEY_ID=$(echo $account_credentials | jq -r '.Credentials.AccessKeyId')
        export AWS_SECRET_ACCESS_KEY=$(echo $account_credentials | jq -r '.Credentials.SecretAccessKey')
        export AWS_SESSION_TOKEN=$(echo $account_credentials | jq -r '.Credentials.SessionToken')
        calculateInventory "$account_name" ""
        export AWS_ACCESS_KEY_ID=$ORG_AWS_ACCESS_KEY_ID
        export AWS_SECRET_ACCESS_KEY=$ORG_AWS_SECRET_ACCESS_KEY
        export AWS_SESSION_TOKEN=$ORG_AWS_SESSION_TOKEN
    done
}

if [ $SCAN_ORGANIZATION = "TRUE" ]
then
    for PROFILE in $(echo $AWS_PROFILE | sed "s/,/ /g")
    do
        ORGANIZATIONS=$(($ORGANIZATIONS + 1))
        PROFILE_STRING="--profile $PROFILE"
        doAnalyzeOrganization "$PROFILE_STRING"
    done

    if [ -z "$PROFILE" ]
    then
        ORGANIZATIONS=1
        doAnalyzeOrganization ""
    fi
else
    for PROFILE in $(echo $AWS_PROFILE | sed "s/,/ /g")
    do
        # Profile set
        PROFILE_STRING="--profile $PROFILE"
        ACCOUNTS=$(($ACCOUNTS + 1))
        calculateInventory "$PROFILE" "$PROFILE_STRING"
    done

    if [ -z "$PROFILE" ]
    then
        # No profile argument, run AWS CLI default
        ACCOUNTS=1
        calculateInventory "" ""
    fi
fi

ECS_FARGATE_VCPUS=$(($ECS_FARGATE_CPUS / 1024))
LAMBDA_VCPUS=$(($LAMBDA_MEMORY_TOTAL / 1024))
TOTAL_VCPUS=$(($EC2_INSTANCE_VCPU + $ECS_FARGATE_VCPUS + $LAMBDA_VCPUS))

textoutput
