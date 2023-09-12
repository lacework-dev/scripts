# OCI Usage Metrics
This directory contains a simple python script that can be executed in the OCI Cloud Shell to capture information about active counts per resource type.

## Policy requirements
The script uses the search API to query resources in a tenancy. The user profile (`DEFAULT` profile in oci config) that runs the script needs the correct set of policies to run it successfully. These policies are the
same, or weaker than those needed to *collect* the resource information in a Lacework integration, which is presented in [the terraform script](https://github.com/lacework/terraform-oci-config/blob/main/main.tf).

## Run the script

1. Login to the Console in the tenancy and region with most data volume.
2. Click the Cloud Shell icon in the Console header. Note that Cloud Shell will execute commands against the region selected in the Console's Region selection menu when Cloud Shell was started.
3. Clone this repoisitory
    ```
    git clone https://github.com/lacework-dev/scripts.git
    ```
4. Change to the directory containing the python script
    ```
    cd scripts/lw-oci-integration/usage_metrics/
    ```
5. Run the script
   ```
   python oci_usage_metrics.py
   ```
6. Verify csv file exists
   ```
   ls -l OCIUsageMetrics.csv 
   ```

## Downloading the csv File

To download a file from Cloud Shell:

1. Click the Cloud Shell menu at the top left of the Cloud Shell window and select Download. The File Download dialog appears:
2. Type in the name of the file in your home directory that you want to download, should be `OCIUsageMetrics.csv`.
3. Click the Download button.
4. The File Transfer dialog will indicate the status of the download.
