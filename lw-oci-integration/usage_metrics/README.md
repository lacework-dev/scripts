# OCI Usage Metrics
This directory contains a simple python script that can be executed in the OCI Cloud Shell to capture information about active counts per resource type.

## Policy requirements
The script uses the search API to query resources in a tenancy. The user profile (`DEFAULT` profile in oci config) that runs the script needs the correct set of policies to run it successfully. These policies are the
same, or weaker than those needed to *collect* the resource information in a Lacework integration, which is presented in [the terraform script](https://github.com/lacework/terraform-oci-config/blob/main/main.tf).

## Running the script

1. Login to the Console in the tenancy and region with most data volume.
2. Click the Cloud Shell icon in the Console header. Note that Cloud Shell will execute commands against the region selected in the Console's Region selection menu when Cloud Shell was started.
3. Run Python:
    ```
    user@cloudshell:oci (us-phoenix-1)$ python3
    Python 3.6.8 (default, Oct  1 2020, 20:32:44) 
    [GCC 4.8.5 20150623 (Red Hat 4.8.5-44.0.3)] on linux
    Type "help", "copyright", "credits" or "license" for more information.
    >>> 
    ```
### Generate CSV with data count information
To run the code, you can either
1. copy the contents of `oci_usage_metrics.py` in the console or 
2. use the upload file (https://docs.oracle.com/en-us/iaas/Content/API/Concepts/devcloudshellgettingstarted.htm#ariaid-title3) and run `python oci_usage_metrics.py`

## Downloading the File
To download a file from Cloud Shell:

1. Click the Cloud Shell menu at the top left of the Cloud Shell window and select Download. The File Download dialog appears:
2. Type in the name of the file in your home directory that you want to download, should be `OCIUsageMetrics.csv`.
3. Click the Download button.
4. The File Transfer dialog will indicate the status of the download.
