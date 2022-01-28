# Overview

BASH script to produce a GCP resource breakdown and total resource count.
It examines every project in the current org. that the executing user has access to (see Roles below).
If a project request receives permission denied, an error will be displayed on screen, but the remaining projects will still be examined.

# Pre-requisites

A Unix like shell (MacOS/Linux) with gcloud, sed, bc utilities installed is the required execution environment.
We recommend using the [gcp cloud shell](https://console.cloud.google.com/home/dashboard?cloudshell=true) - it has all the dependencies.

# Roles

The user executing the script must have roles/cloudassset.viewer and roles/serviceusage.serviceUsageConsumer on the parent of the resources to be examined.

### A) We recommend granting at the org level:

`gcloud organizations add-iam-policy-binding TARGET_ORGANIZATION_ID \
     --member user:USER_ACCOUNT_EMAIL \
     --role roles/cloudasset.viewer`

`gcloud organizations add-iam-policy-binding TARGET_ORGANIZATION_ID \
     --member user:USER_ACCOUNT_EMAIL \
     --role roles/serviceusage.serviceUsageConsumer`

### B) Alternative is granting for each project to be examined:

`gcloud projects add-iam-policy-binding TARGET_PROJECT_ID \
     --member user:USER_ACCOUNT_EMAIL \
     --role roles/cloudasset.viewer`

`gcloud projects add-iam-policy-binding TARGET_PROJECT_ID \
     --member user:USER_ACCOUNT_EMAIL \
     --role roles/serviceusage.serviceUsageConsumer`

# API enablement

Script requires access to cloudasset API.

### A) We recommend granting for all projects in the org:

1. Download the script cloudasset_enable.sh

wget https://github.com/lacework-dev/scripts/blob/main/resource_management/gcp/cloudasset_enable.sh

2. Run the script:

`chmod +x ./cloudasset_enable.sh; mkdir -p /tmp/lacework; ./cloudasset_enable.sh 2>&1 | tee /tmp/lacework/enable_output`

### B) Alternative is manually granting for each project to be examined:

`gcloud --project <project_id> services enable cloudasset.googleapis.com`

# Usage

1. Download the script:

wget https://github.com/lacework-dev/scripts/blob/main/resource_management/gcp/gcp_asset_breakdown.sh

2. Run the script:

`chmod +x ./gcp_asset_breakdown.sh; mkdir -p /tmp/lacework; ./gcp_asset_breakdown.sh 2>&1 | tee /tmp/lacework/output`

# Results

Summary output is displayed on screen.
When the script finishes, we recommend uploading the contents of directory:

`/tmp/lacework/`

This can be done in GCP cloud shell by clicking on the more icon (vertical '...') and selecting download.
