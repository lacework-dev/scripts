
## Lacework OCI Integration

The OCI Terraform scripts can be run locally or through an OCI cloud shell. Using the OCI cloud shell is recommended, as it comes with Terraform pre-installed and helps with authentication.

## Prepare to run Terraform locally (Option 1)

Before using the Terraform script, you must create the required environment variables to access your OCI tenant. The recommended way to do this is:

1. Clone this github repo. For example:
   ```
   git clone https://github.com/lacework-dev/scripts.git
   ```
2. Change directory to the `lw-oci-integration/tf` folder and copy the `vars.tfvars.example` to `terraform.tfvars`.
3. Update the values in this file to align with your administrative OCI user access.
    ```
    region="<YOUR HOME REGION  (e.g. us-ashburn-1)>"
    tenancy_ocid="<YOUR OCI TEANCY OCID>"
    user_ocid="<YOUR OCI USER OCID>"
    fingerprint="<YOUR KEY FINGER PRINT>"
    private_key_path="<YOUR KEY KEY PATH (e.g. ~/.oci/myocikey.pem)>"
    ```
4. Install the Lacework CLI and configure with your API key. For more information, see the [Lacework CLI Guide](https://docs.lacework.net/cli/).

## Prepare to run Terraform via OCI Cloud Shell (Option 2)

1. Open the OCI cloud shell. For example:
   1. Log in to the OCI console.
   2. Click on the '<>' icon (developer tools), located on the top right of the OCI web console.
   3. Select Cloud Shell.
2. Clone this github repo. For example:
    ```
    git clone https://github.com/lacework-dev/scripts.git
    ```
3. Change directory to the `lw-oci-integration/tf` folder and copy `vars.tfvars.example` to `terraform.tfvars`.
4. OCI auth is automatically handled by the cloud shell. To use this, we modify a couple of files:
   * In `terraform.tfvars`, set the `region` and `tenancy_ocid` as appropriate. The `user_ocid`, `fingerprint` 
and `private_key_path` fields are not applicable when using cloud shell. The `group_name`, `user_name` and `policy_name` will be
created by the Terraform script for the Lacework OCI integration. They can be left as they are, or modified if required.
     
     ```
     region="<YOUR HOME REGION  (e.g. us-ashburn-1)>"
     tenancy_ocid="<YOUR OCI TEANCY OCID>"
     user_ocid=null
     fingerprint=null
     private_key_path=null
     
     ```
5. Install the Lacework CLI (if it is not already installed) and configure with your API key. For more information, see the [Lacework CLI Guide](https://docs.lacework.net/cli/).
     
   **Note:** The step to install the CLI may fail with permission denied on the OCI cloud shell. If this happens, follow these steps:
   1. Download the install script
      ```
      curl https://raw.githubusercontent.com/lacework/go-sdk/main/cli/install.sh
      ```
   2. Install to the present working directory (PWD):
      ```
      ./install.sh -d $PWD
      ```
   3. Modify the path (temporary) to include the PWD:
      ```
      export PATH=$PATH:$PWD
      ```

Now, continue following instructions on [Lacework CLI Guide](https://docs.lacework.net/cli/) to configure your API key.

# Running Terraform (common to options 1 and option 2)

1. Once the file is updated, run the following command to initialize Terraform:
   ```
   terraform init
   ```

2. Now verify and plan the Terraform using this command:
   ```
   terraform plan
   ```
3. If everything looks good, apply the change using the following command:
   ```
   terraform apply -auto-approve
   ```
4. After the plan is applied, a Lacework cloud account policy is created locally under ~/.oci/lacework_cloud_account.json. You can post this file to Lacework via the Lacework CLI to create your integration: 
   ```
   lacework api post /api/v2/CloudAccounts -d "$(cat ~/.oci/lacework_cloud_account.json)"
   ```


| **Note:**          |
|:---------------------------|
| You may need to use the `--profile` option for the lacework-cli depending on your configuration. The default profile will be used if one is not specified.     |
