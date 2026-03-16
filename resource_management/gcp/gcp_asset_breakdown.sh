#!/bin/bash

STAR=*
FILEENDING=".assets"

echo "Installing utility bc"
sudo apt install -y bc

echo "This script gives a breakdown of resources by asset type for all projects the authenticated account has access to"
echo "For pre-requisites, including permissions, please see the README"
echo "It is recommened to use gcp's cloud shell to execute the script"
echo "Recommended invocation: chmod +x ./gcp_asset_breakdown.sh; mkdir -p /tmp/lacework; ./gcp_asset_breakdown.sh 2>&1 | tee /tmp/lacework/output"
echo ""

mkdir -p /tmp/lacework
gcloud config set accessibility/screen_reader false

var=$(gcloud projects list --filter='lifecycleState:ACTIVE' | sed "1 d" | cut -d ' ' -f 1)
number_projects=$(echo "$var" | wc -l)

echo "==> Project list:"
echo $var | tr " " "\n"
echo "==> Total number of projects = $number_projects"

read -p "Continue to summarise assetTypes and count on all projects? " -n 1 -r
echo    # (optional) move to a new line
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    [[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1 # handle exits from shell or function but don't exit interactive shell
fi

for val in $var; do
    echo "=> Examining Project $val"
    if gcloud asset list --page-size=1000 --project $val | grep "assetType" > /tmp/lacework/$val$FILEENDING
    then
       echo "==> Done."
    else
       echo "==> Error examining."
    fi
    echo "***************************************"
done
# Concatenate all assets into a single file, count assets, reduce each line to just the asset count and then sum the counts to find the total.
cat /tmp/lacework/*.assets > /tmp/lacework/combined; cat /tmp/lacework/combined | sort | uniq -c | sort -bgr > /tmp/lacework/combined_count
echo "asset-type breakdown"
cat /tmp/lacework/combined_count
sed 's/assetType.*$//g' /tmp/lacework/combined_count > /tmp/lacework/combined_count_numbers
total_assets=$(paste -sd+ /tmp/lacework/combined_count_numbers | bc)
echo ""
echo ""
echo "Total assets=$total_assets"
echo ""
echo "Please take a copy of the contents of directory /tmp/lacework and send for more analysis"
echo "In GCP cloudshell this can be done by clicking on more (the vertical \"...\") and selecting Download"
