#!/bin/bash
# Preflight check for Lacework AWS integrations
# Requires awscli and jq
# You can also run this in AWS Cloudshell where these are preinstalled.

OK="✅"
NO="❌"
WARN="⚠️"

echo "********************************************"
echo "       Lacework AWS Preflight Check"
echo "********************************************"

function has_cloudtrail () {
  read -p "Do you have an existing Cloudtrail in your AWS account? (Y/N) " confirm
  if [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]]; then
    echo ""
    PS3='Please choose the AWS ARN of the Cloudtrail you would like to use: '
    select ct_arn in $(aws cloudtrail list-trails | jq -r '.Trails[] | .TrailARN'); do
        export CT_ARN=$ct_arn
        break;
    done
  else
    echo ""
    echo "Lacework can create a new AWS Cloudtrail for you."
    echo "Please follow the docs for installing Lacework using Terraform or Cloudformation:"
    echo ""
    echo "https://support.lacework.com/hc/en-us/articles/360057092034"
    exit 0
  fi
}

function get_trail_settings () {
  arn=$1
  aws cloudtrail get-trail --name $arn > /dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    echo "Unable to access the Cloudtrail ARN you provided:"
    echo $arn
    exit 1
  fi
  json=$(aws cloudtrail get-trail --name $arn)
  #echo $json
  export TRAIL=$(echo $json | jq -r '.Trail | .Name')
  export BUCKET=$(echo $json | jq -r '.Trail | .S3BucketName')
  export SNSTOPIC=$(echo $json | jq -r '.Trail | .SnsTopicName')
}

function check_encryption () {
  bucket=$1
  err=$((aws s3api get-bucket-encryption --bucket $bucket) 2>&1)
  if echo $err | grep -q AccessDenied; then
    export SSEALGO="AccessDenied"
  elif echo $err | grep -q ServerSideEncryptionConfigurationNotFoundError; then
    export SSEALGO="None"
  else
    json=$(aws s3api get-bucket-encryption --bucket $bucket)
    export SSEALGO=$(echo $json | jq -r '.ServerSideEncryptionConfiguration | .Rules | .[] | .ApplyServerSideEncryptionByDefault | .SSEAlgorithm')
  fi
}

has_cloudtrail
echo "Analyzing..."
get_trail_settings $CT_ARN
check_encryption $BUCKET

if [[ ! -z $CT_ARN ]]; then
  echo "${OK}  Cloudtrail exists and is accessible."
else
  echo "${NO}  Cloudtrail is not accessible."
fi

if [[ $SNSTOPIC != "null" ]]; then
  echo "${OK}  SNS topic exists and is accessible."
else
  echo "${NO}  SNS topic does not exist."
fi

if [[ $SSEALGO == "aws:kms" ]]; then
  echo "${WARN}  AWS KMS encryption detected on your S3 Bucket. Please review the docs:"
  echo ""
  echo "https://support.lacework.com/hc/en-us/articles/360019127414-Integration-with-S3-Buckets-Using-Server-Side-Encryption-with-AWS-KMS-Managed-Keys"
elif [[ $SSEALGO == "AES256" ]]; then
  echo "${OK}  Amazon S3 key encryption detected on your S3 Bucket. You may proceed with Lacework installation."
elif [[ $SSEALGO == "AccessDenied" ]]; then
  echo "${NO}  Unable to access S3 bucket. If your Cloudtrail logs are stored in a different account, please install the Lacework integration there."
elif [[ $SSEALGO == "None" ]]; then
  echo "${OK}  No encryption detected on your S3 bucket. You may proceed with Lacework installation."
fi
