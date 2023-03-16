#!/bin/bash
# Script to fetch AWS inventory for Lacework sizing.
# Requirements: awscli v2, jq

# Run ./lw_aws_inventory.sh -h for help on how to run the script.
# Or just read the text in showHelp below.

function showHelp {
  echo "lw_aws_inventory.sh is a tool for estimating Lacework license vCPUs in an AWS environment."
  echo "It leverages the AWS CLI and by default the default profile that’s either configured using"
  echo "environment variables or configuration files in the ~/.aws folder. The script provides"
  echo "output in a CSV format to be imported into a spreadsheet, as well as an easy-to-read summary."
  echo ""
  echo "Note the following about the script:"
  echo "* Requires AWS CLI v2 to run"
  echo "* Works great in a cloud shell"
  echo "* It has been verified to work on Mac and Linux based systems"
  echo "* Has been observed to work with Windows Subsystem for Linux to run on Windows"
  echo "* Not compatible with Cygwin on Windows"
  echo "* Run using the following syntax: ./lw_aws_inventory.sh, sh lw_aws_inventory.sh will not work"
  echo ""
  echo "Available flags:"
  echo " -p       Comma separated list of AWS CLI profiles to scan."
  echo "          If not specified, the tool will use the connection information that the AWS CLI picks"
  echo "          by default, which will either be whatever is set in environment variables or as the"
  echo "          default profile."
  echo "          ./lw_aws_inventory.sh -p default"
  echo "          ./lw_aws_inventory.sh -p development,test,production"
  echo " -r       Comma-separated list of regions to scan."
  echo "          By default, the script will attempt to collect sizing data for all regions returned by"
  echo "          aws ec2 describe-regions. This is by default a list of 17 regions. This parameter will"
  echo "          limit the scope to a pre-defined set of regions, which will avoid errors when regions"
  echo "          are disabled and speed up the scan."
  echo "          ./lw_aws_inventory.sh -r us-east-1"
  echo "          ./lw_aws_inventory.sh -r us-east-1,us-west-1"
  echo " -o       Scan a complete AWS organization"
  echo "          This uses aws organizations list-accounts to determine what accounts are in an"
  echo "          organization and assumes a cross account role to scan each account in the organization,"
  echo "          except for the master account, which is scanned directly."
  echo "          The role typically used cross-account access is OrganizationAccountAccessRole, which"
  echo "          is accessed from a user in the master account."
  echo "          ./lw_aws_inventory.sh -o OrganizationAccountAccessRole"
  echo " -a       Scan a specific account within an organization"
  echo "          This would leverage the cross-account role defined using the -o parameter to only"
  echo "          scan an individual account within an AWS organisation."
  echo "          ./lw_aws_inventory.sh -o OrganizationAccountAccessRole -a 1234567890"
  echo " -g       Specifies a script to be generated that contains a call for each account to be analyzed."
  echo "          This is useful for analyzing AWS organizations with many accounts to break up the analysis"
  echo "          into smaller chunks."
  echo "          ./lw_aws_inventory.sh -o OrganizationAccountAccessRole -a 1234567890 -g script.sh"
  echo "          ./script.sh"
  echo " --output Specify level of output"
  echo "          all         - CSV and summary"
  echo "          summary     - Summary only"
  echo "          csv         - CSV only"
  echo "          csvnoheader - CVS only without header"
  echo "          ./lw_aws_inventory.sh --ouptput csv"
}

AWS_PROFILE=""
export AWS_MAX_ATTEMPTS=20
REGIONS=""
ORG_ACCESS_ROLE=""
ORG_SCAN_ACCOUNT=""
PRINT_CSV_DETAILS="true"
PRINT_CSV_HEADER="true"
PRINT_SUMMARY="true"
GENERATE_SCRIPT=""

ORG_AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
ORG_AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
ORG_AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN

CSV_HEADER="\"Profile\", \"Account ID\", \"Regions\", \"EC2 Instances\", \"EC2 vCPUs\", \"ECS Fargate Clusters\", \"ECS Fargate Running Containers/Tasks\", \"ECS Fargate CPU Units\", \"ECS Fargate License vCPUs\", \"Lambda Functions\", \"MB Lambda Memory\", \"Lambda License vCPUs\", \"Total vCPUSs\""

# Usage: ./lw_aws_inventory.sh
while getopts ":p:o:r:a:-:g:" opt; do
  case ${opt} in
    p )
      AWS_PROFILE=$OPTARG
      ;;
    o )
      ORG_ACCESS_ROLE=$OPTARG
      ;;
    a )
      ORG_SCAN_ACCOUNT=$OPTARG
      ;;
    g )
      GENERATE_SCRIPT=$OPTARG
      ;;
    r )
      REGIONS=$OPTARG
      ;;
    -)
        case "${OPTARG}" in
            #Default configuration is to print CSV and summary. This section overrides those settings as needed
            output)
                output="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                case "${output}" in
                  csv)
                    PRINT_SUMMARY="false"
                    ;;
                  summary)
                    PRINT_CSV_DETAILS="false"
                    PRINT_CSV_HEADER="false"
                    ;;
                  all)
                    #Do nothing, default configuration
                    ;;
                  csvnoheader)
                    PRINT_CSV_HEADER="false"
                    PRINT_SUMMARY="false"
                    ;;
                  *)
                    echo "Invalid argument. Valid options for --output: csv, summary, all, csvnoheader"
                    showHelp
                    exit  
                    ;;
                esac
                ;;
            *)
              showHelp
              exit
              ;;
        esac;;    
    \? )
      showHelp
      exit 1
      ;;
    : )
      showHelp
      exit 1
      ;;
  esac
done
shift $((OPTIND -1))

#Check AWS CLI pre-requisites
AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d " " -f1 | cut -d "/" -f2)
if [[ $AWS_CLI_VERSION = 1* ]]
then
  echo The script requires AWS CLI v2 to run. The current version installed is version $AWS_CLI_VERSION.
  echo See https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html for instructions on how to upgrade.
  exit
fi

#Ensure the script runs with the BASH shell
echo $BASH | grep -q "bash"
if [ $? -ne 0 ]
then
  echo The script is running using the incorrect shell.
  echo Use ./lw_aws_inventory.sh to run the script using the required shell, bash.
  exit
fi

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

function cleanup {
  # Revert to original AWS CLI configuration if script is stopped during execution
  export AWS_ACCESS_KEY_ID=$ORG_AWS_ACCESS_KEY_ID
  export AWS_SECRET_ACCESS_KEY=$ORG_AWS_SECRET_ACCESS_KEY
  export AWS_SESSION_TOKEN=$ORG_AWS_SESSION_TOKEN
}
trap cleanup EXIT

function getAccountId {
  local profile_string=$1
  aws $profile_string sts get-caller-identity --query "Account" --output text
}

function getRegions {
  local profile_string=$1
  aws $profile_string ec2 describe-regions --output json | jq -r '.[] | .[] | .RegionName'
}

function getEC2Instances {
  local profile_string=$1
  local r=$2
  local instances=$(aws $profile_string ec2 describe-instances --query 'Reservations[*].Instances[*].[InstanceId]' --filters Name=instance-state-name,Values=running --region $r --output json --no-cli-pager  2>&1)
  if [[ $instances = [* ]] 
  then
    echo $(echo $instances | jq 'flatten | length')
  else
    echo "-1"
  fi
}

function getEC2InstacevCPUs {
  local profile_string=$1
  local r=$2
  cpucounts=$(aws $profile_string ec2 describe-instances --query 'Reservations[*].Instances[*].[CpuOptions]' --filters Name=instance-state-name,Values=running --region $r --output json --no-cli-pager | jq  '.[] | .[] | .[] | .CoreCount * .ThreadsPerCore')
  returncount=0
  for cpucount in $cpucounts; do
    returncount=$(($returncount + $cpucount))
  done
  echo "${returncount}"
}

function getECSFargateClusters {
  local profile_string=$1
  local r=$2
  aws $profile_string ecs list-clusters --region $r --output json --no-cli-pager | jq -r '.clusterArns[]'
}

function getECSFargateRunningTasks {
  local profile_string=$1
  local r=$2
  local ecsfargateclusters=$3
  local RUNNING_FARGATE_TASKS=0
  for c in $ecsfargateclusters; do
    allclustertasks=$(aws $profile_string ecs list-tasks --region $r --output json --cluster $c --no-cli-pager | jq -r '.taskArns | join(" ")')
    while read -r batch; do
      if [ -n "${batch}" ]; then
        fargaterunningtasks=$(aws $profile_string ecs describe-tasks --region $r --output json --tasks $batch --cluster $c --no-cli-pager | jq '[.tasks[] | select(.launchType=="FARGATE") | select(.lastStatus=="RUNNING")] | length')
        RUNNING_FARGATE_TASKS=$(($RUNNING_FARGATE_TASKS + $fargaterunningtasks))
      fi
    done < <(echo $allclustertasks | xargs -n 90)
  done

  echo "${RUNNING_FARGATE_TASKS}"
}

function getECSFargateRunningCPUs {
  local profile_string=$1
  local r=$2
  local ecsfargateclusters=$3
  local RUNNING_FARGATE_CPUS=0
  for c in $ecsfargateclusters; do
    allclustertasks=$(aws $profile_string ecs list-tasks --region $r --output json --cluster $c --no-cli-pager | jq -r '.taskArns | join(" ")')
    while read -r batch; do
      if [ -n "${batch}" ]; then
        cpucounts=$(aws $profile_string ecs describe-tasks --region $r --output json --tasks $batch --cluster $c --no-cli-pager | jq '[.tasks[] | select(.launchType=="FARGATE") | select(.lastStatus=="RUNNING")] | .[].cpu | tonumber')

        for cpucount in $cpucounts; do
          RUNNING_FARGATE_CPUS=$(($RUNNING_FARGATE_CPUS + $cpucount))
        done
      fi
    done < <(echo $allclustertasks | xargs -n 90)
  done

  echo "${RUNNING_FARGATE_CPUS}"
}

function getLambdaFunctions {
  local profile_string=$1
  local r=$2
  aws $profile_string lambda list-functions --region $r --output json --no-cli-pager | jq '.Functions | length'
}

function getLambdaFunctionMemory {
  local profile_string=$1
  local r=$2
  memoryForAllFunctions=$(aws $profile_string lambda list-functions --region $r --output json --no-cli-pager | jq '.Functions[].MemorySize')
  TOTAL_LAMBDA_MEMORY=0
  for memory in $memoryForAllFunctions; do
    TOTAL_LAMBDA_MEMORY=$(($TOTAL_LAMBDA_MEMORY + $memory))
  done
  
  echo "${TOTAL_LAMBDA_MEMORY}"
}

function calculateInventory {
  local account_name=$1
  local profile_string=$2
  local accountid=$(getAccountId "$profile_string")
  local accountEC2Instances=0
  local accountEC2vCPUs=0
  local accountECSFargateClusters=0
  local accountECSFargateRunningTasks=0
  local accountECSFargateCPUs=0
  local accountLambdaFunctions=0
  local accountLambdaMemory=0
  local accountTotalvCPUs=0

  if [[ $PRINT_CSV_DETAILS == "true" ]]
  then
    printf "$account_name, $accountid,"
  fi
  local regionsToScan=$(echo $REGIONS | sed "s/,/ /g")
  if [ -z "$regionsToScan" ]
  then
      # Regions to scan not set, get list from AWS
      regionsToScan=$(getRegions)
  fi

  for r in $regionsToScan; do
    if [[ $PRINT_CSV_DETAILS == "true" ]]
    then
      printf " $r"
    fi

    instances=$(getEC2Instances "$profile_string" "$r")
    if [[ $instances < 0 ]]
    then
      printf " (ERROR: No access to $r)"
    else
      EC2_INSTANCES=$(($EC2_INSTANCES + $instances))
      accountEC2Instances=$(($accountEC2Instances + $instances))

      ec2vcpu=$(getEC2InstacevCPUs "$profile_string" "$r")
      EC2_INSTANCE_VCPU=$(($EC2_INSTANCE_VCPU + $ec2vcpu))
      accountEC2vCPUs=$(($accountEC2vCPUs + $ec2vcpu))

      ecsfargateclusters=$(getECSFargateClusters "$profile_string" "$r")
      ecsfargateclusterscount=$(echo $ecsfargateclusters | wc -w | xargs)
      ECS_FARGATE_CLUSTERS=$(($ECS_FARGATE_CLUSTERS + $ecsfargateclusterscount))
      accountECSFargateClusters=$(($accountECSFargateClusters + $ecsfargateclusterscount))

      ecsfargaterunningtasks=$(getECSFargateRunningTasks "$profile_string" "$r" "$ecsfargateclusters")
      ECS_FARGATE_RUNNING_TASKS=$(($ECS_FARGATE_RUNNING_TASKS + $ecsfargaterunningtasks))
      accountECSFargateRunningTasks=$(($accountECSFargateRunningTasks + $ecsfargaterunningtasks))

      ecsfargatecpu=$(getECSFargateRunningCPUs "$profile_string" "$r" "$ecsfargateclusters")
      ECS_FARGATE_CPUS=$(($ECS_FARGATE_CPUS + $ecsfargatecpu))
      accountECSFargateCPUs=$(($accountECSFargateCPUs + $ecsfargatecpu))

      lambdafunctions=$(getLambdaFunctions "$profile_string" "$r")
      LAMBDA_FUNCTIONS=$(($LAMBDA_FUNCTIONS + $lambdafunctions))
      accountLambdaFunctions=$(($accountLambdaFunctions + $lambdafunctions))

      lambdamemory=$(getLambdaFunctionMemory "$profile_string" "$r")
      LAMBDA_MEMORY_TOTAL=$(($LAMBDA_MEMORY_TOTAL + $lambdamemory))
      accountLambdaMemory=$(($accountLambdaMemory + $lambdamemory))
    fi
  done

  accountECSFargatevCPUs=$(($accountECSFargateCPUs / 1024))
  accountLambdavCPUs=$(($accountLambdaMemory / 1024))
  accountTotalvCPUs=$(($accountEC2vCPUs + $accountECSFargatevCPUs + $accountLambdavCPUs))

    if [[ $PRINT_CSV_DETAILS == "true" ]]
    then
      echo , "$accountEC2Instances", "$accountEC2vCPUs", "$accountECSFargateClusters", "$accountECSFargateRunningTasks", "$accountECSFargateCPUs", "$accountECSFargatevCPUs", "$accountLambdaFunctions", "$accountLambdaMemory", "$accountLambdavCPUs", "$accountTotalvCPUs"
    fi
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
  echo "ECS Clusters:                    $ECS_FARGATE_CLUSTERS"
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
  echo "  EC2 vCPUs:            $EC2_INSTANCE_VCPU"
  echo "+ ECS Fargate vCPUs:    $ECS_FARGATE_VCPUS"
  echo "+ Lambda License vCPUs: $LAMBDA_VCPUS"
  echo "----------------------------"
  echo "= Total vCPUs:          $TOTAL_VCPUS"
}

function analyzeOrganization {
    local org_profile_string=$1
    local orgAccountId=$(getAccountId "$org_profile_string")
    local accounts=$(aws $org_profile_string organizations list-accounts | jq -c '.Accounts[]' | jq -c '{Id, Name}')
    if [ -n "$ORG_SCAN_ACCOUNT" ]
    then
      local account_name=$(echo $accounts | jq -r --arg account "$ORG_SCAN_ACCOUNT" 'select(.Id==$account) | .Name')
      analyzeOrganizationAccount "$org_profile_string" "$ORG_SCAN_ACCOUNT" "$account_name"
    else
      for account in $(echo $accounts | jq -r '.Id')
      do
          local account_name=$(echo $accounts | jq -r --arg account "$account" 'select(.Id==$account) | .Name')
          if [[ $orgAccountId == $account ]]
          then
            # Found master account, role most likely don't exist, just connnect directly
            ACCOUNTS=$(($ACCOUNTS + 1))
            calculateInventory "$account_name" "$org_profile_string"
          else
            analyzeOrganizationAccount "$org_profile_string" "$account" "$account_name"
          fi
      done
    fi
}

function analyzeOrganizationAccount {
  local org_profile_string=$1
  local account=$2
  local account_name=$3

  local account_credentials=$(aws $org_profile_string sts assume-role --role-session-name LW-INVENTORY --role-arn arn:aws:iam::$account:role/$ORG_ACCESS_ROLE 2>&1)
  if [[ $account_credentials = {* ]] 
  then
    #Got ok credential back, do analysis
    ACCOUNTS=$(($ACCOUNTS + 1))
    export AWS_ACCESS_KEY_ID=$(echo $account_credentials | jq -r '.Credentials.AccessKeyId')
    export AWS_SECRET_ACCESS_KEY=$(echo $account_credentials | jq -r '.Credentials.SecretAccessKey')
    export AWS_SESSION_TOKEN=$(echo $account_credentials | jq -r '.Credentials.SessionToken')
    calculateInventory "$account_name" ""
    export AWS_ACCESS_KEY_ID=$ORG_AWS_ACCESS_KEY_ID
    export AWS_SECRET_ACCESS_KEY=$ORG_AWS_SECRET_ACCESS_KEY
    export AWS_SESSION_TOKEN=$ORG_AWS_SESSION_TOKEN
  else
    #Failed to connect, print error message
    echo "ERROR: Failed to connect to account \"$account_name\" ($account). ${account_credentials}"
    echo "aws $org_profile_string sts assume-role --role-session-name LW-INVENTORY --role-arn arn:aws:iam::$account:role/$ORG_ACCESS_ROLE"
  fi
}

function runAnalysis {
  if [[ $PRINT_CSV_HEADER == "true" ]]
  then
    echo $CSV_HEADER
  fi

  if [ -n "$ORG_ACCESS_ROLE" ]
  then
      for PROFILE in $(echo $AWS_PROFILE | sed "s/,/ /g")
      do
          ORGANIZATIONS=$(($ORGANIZATIONS + 1))
          PROFILE_STRING="--profile $PROFILE"
          analyzeOrganization "$PROFILE_STRING"
      done

      if [ -z "$PROFILE" ]
      then
          ORGANIZATIONS=1
          analyzeOrganization ""
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

  if [[ $PRINT_SUMMARY == "true" ]]
  then
    textoutput
  fi
}

function generateOrganizationScript {
  local profile=$1
  local cliProfileString=$2
  local regionString=$3
  local orgMasterAccountID=$(getAccountId "$cliProfileString")
  local accounts=$(aws $cliProfileString organizations list-accounts | jq -c '.Accounts[]' | jq -c '{Id, Name}')

  for account in $(echo $accounts | jq -r '.Id')
  do
      if [[ $orgMasterAccountID == $account ]]
      then
        echo "$0 $profile  $regionString --output csvnoheader"  >> $GENERATE_SCRIPT
      else
        echo "$0 $profile -o $ORG_ACCESS_ROLE -a $account $regionString --output csvnoheader"  >> $GENERATE_SCRIPT
      fi
  done
}

function generateScript {
  echo Generating script $GENERATE_SCRIPT

  echo "#!/bin/bash" > $GENERATE_SCRIPT
  echo "echo $CSV_HEADER" >> $GENERATE_SCRIPT
  chmod +x $GENERATE_SCRIPT

  local scriptRegions=""
  if [ -n "$REGIONS" ]
  then
    scriptRegions="-r $REGIONS"
  fi
  if [ -n "$ORG_ACCESS_ROLE" ]
  then
      for PROFILE in $(echo $AWS_PROFILE | sed "s/,/ /g")
      do
        generateOrganizationScript "-p $PROFILE" "--profile $PROFILE" "$scriptRegions"
      done

      if [ -z "$PROFILE" ]
      then
        generateOrganizationScript "" "" "$scriptRegions"
      fi
  else
      for PROFILE in $(echo $AWS_PROFILE | sed "s/,/ /g")
      do
        echo "$0 $regionString -p $PROFILE $scriptRegions --output csvnoheader" >> $GENERATE_SCRIPT
      done

      if [ -z "$PROFILE" ]
      then
        echo "$0 $regionString $scriptRegions --output csvnoheader"  >> $GENERATE_SCRIPT
      fi
  fi
}

if [[ -n $GENERATE_SCRIPT ]]
then
  generateScript
else
  runAnalysis
fi
