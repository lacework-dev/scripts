#!/bin/bash

if [ -z "$1" ];
then
  echo "Usage: ${0} [policy directory] e.g. ${0} policies/opal"
  exit 1
fi

if [ ! -d "$1" ];
then
    echo "${1} is not a directory"
    exit 1
fi

if ! ls ${1}/*/*/policy.rego > /dev/null 2>&1;
then
    echo "${1} does not contain policies (should be the directory that contains your individual policies e.g. policies/opal)"
    exit 1
fi

if grep -q 'import data.lacework.iac' $1/*/*/policy.rego;
then
    echo "${1} already has policies with the new package names - this script should not be re-applied. Revert changes to your policies if you need to run this script again."
    exit 1 
fi

sed -i.lw_tmp 's/import data.lacework/import data.lacework.iac/g' $1/*/*/policy.rego
sed -i.lw_tmp 's/import data.arm/import data.lacework.iac.arm/g' $1/*/*/policy.rego
sed -i.lw_tmp 's/import data.aws/import data.lacework.iac.aws/g' $1/*/*/policy.rego
sed -i.lw_tmp 's/import data.azurerm/import data.lacework.iac.azurerm/g' $1/*/*/policy.rego
sed -i.lw_tmp 's/import data.cfn/import data.lacework.iac.cfn/g' $1/*/*/policy.rego
sed -i.lw_tmp 's/import data.gcp/import data.lacework.iac.gcp/g' $1/*/*/policy.rego
sed -i.lw_tmp 's/import data.google/import data.lacework.iac.google/g' $1/*/*/policy.rego
sed -i.lw_tmp 's/import data.k8s/import data.lacework.iac.k8s/g' $1/*/*/policy.rego
sed -i.lw_tmp 's/lacework.allow/iac.allow/g' $1/*/*/policy.rego
sed -i.lw_tmp 's/lacework.deny/iac.deny/g' $1/*/*/policy.rego
sed -i.lw_tmp 's/lacework.resource/iac.resource/g' $1/*/*/policy.rego
sed -i.lw_tmp 's/lacework.missing/iac.missing/g' $1/*/*/policy.rego
sed -i.lw_tmp 's/lacework.input_type/iac.input_type/g' $1/*/*/policy.rego
sed -i.lw_tmp 's/lacework.input_resource_types/iac.input_resource_types/g' $1/*/*/policy.rego

# To support both GNU and BSD sed we needed to generate some swap files, delete these now.
rm $1/*/*/*.lw_tmp