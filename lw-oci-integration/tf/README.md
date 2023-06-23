
## Lacework OCI Integration

The OCI Terraform scripts can be run locally or through an OCI cloud shell. Using the OCI cloud shell is recommended, as it comes with Terraform pre-installed and helps with authentication.

## Prerequisites

1. terraform (recommend >=1.4.6: the version tested)
2. git

Both prerequisites are satisifed by OCI cloud shell.

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

    group_name="lacework_group_security_audit"
    user_name="lacework_user_security_audit"
    policy_name="lacework_policy_security_audit"
    ```

* tenancy_ocid can be retrieved with this cli command:
    ```
    oci iam compartment list --raw-output --query "data[?contains(\"compartment-id\",'.tenancy.')].\"compartment-id\" | [0]"
    ```
* `region` should be in '[region identifier](https://docs.oracle.com/en-us/iaas/Content/General/Concepts/regions.htm)' format, e.g. us-sanjose-1.
* `group_name`, `user_name` and `policy_name` should be unique (not exist already).

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
3. Change directory to the `scripts/lw-oci-integration/tf` folder and copy `vars.tfvars.example` to `terraform.tfvars`.
    ```
    cd scripts/lw-oci-integration/tf
    cp vars.tfvars.example terraform.tfvars
    ```
4. OCI auth is automatically handled by the cloud shell. To use this, modify `terraform.tfvars`:
     ```
     region="<YOUR HOME REGION  (e.g. us-ashburn-1)>"
     tenancy_ocid="<YOUR OCI TEANCY OCID>"
     user_ocid=null
     fingerprint=null
     private_key_path=null

     group_name="lacework_group_security_audit"
     user_name="lacework_user_security_audit"
     policy_name="lacework_policy_security_audit"
     ```
   * `region` and `tenancy_ocid` should be set as appropriate.
   * `user_ocid`, `fingerprint` and `private_key_path` fields are not applicable when using cloud shell and should be set to null.
   * `group_name`, `user_name` and `policy_name` will be created by the Terraform script for the Lacework OCI integration. They can be left as they are, or modified if required. They should be unique.
   * `tenancy_ocid` can be retrieved with this cli command:
       ```
       oci iam compartment list --raw-output --query "data[?contains(\"compartment-id\",'.tenancy.')].\"compartment-id\" | [0]"
       ```
   * `region` should be in '[region identifier](https://docs.oracle.com/en-us/iaas/Content/General/Concepts/regions.htm)' format, e.g. us-sanjose-1.
   
5. Install the Lacework CLI and configure with your API key. For more information, see the [Lacework CLI Guide](https://docs.lacework.net/cli/).
     
   **Note:** The step to install the CLI may fail with permission denied on the OCI cloud shell. If this happens, install as follows:
      ```
      curl https://raw.githubusercontent.com/lacework/go-sdk/main/cli/install.sh | bash -s -- -d /home/oci/bin
      ```
 
Now, continue to the Running Terraform section.

# Running Terraform

1. Run the following command to initialize Terraform:
   ```
   terraform init
   ```

2. Now verify and generate a Terraform plan:
   ```
   terraform plan
   ```
3. If `Terraform Plan` runs successfully with no errors, use the following command to create the required OCI resources:
   ```
   terraform apply -auto-approve
   ```
4. After the Terraform is applied, a Lacework cloud account payload is created locally under `~/.oci/lacework_cloud_account.json`. To create your OCI integration on the Lacework platform, run the following post:
   ```
   lacework api post /api/v2/CloudAccounts -d "$(cat ~/.oci/lacework_cloud_account.json)"
   ```


| **Note:**          |
|:---------------------------|
| You may need to use the `--profile` option for the lacework-cli depending on your configuration. The default profile will be used if one is not specified.     |
