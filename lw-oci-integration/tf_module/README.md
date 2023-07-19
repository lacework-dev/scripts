
## Lacework OCI Integration

The OCI Terraform scripts can be run locally or through an OCI cloud shell. Using the OCI cloud shell is recommended, as it comes with Terraform pre-installed and helps with authentication.

## Prerequisites

1. terraform (recommend >=1.4.6: the version tested)

prerequisites are satisifed by OCI cloud shell.

## Prepare to run Terraform via OCI Cloud Shell

1. Open the OCI cloud shell. For example:
   1. Log in to the OCI web console.
   2. Ensure that your home region is selected in the [**Regions**](https://docs.oracle.com/en-us/iaas/Content/GSG/Concepts/working-with-regions.htm) menu at the top right of the OCI web console. 
   3. Click the Developer Tools icon next to the **Regions** menu and then [**Cloud Shell**](https://docs.oracle.com/en-us/iaas/Content/API/Concepts/cloudshellgettingstarted.htm). The cloud shell should appear with your current region indicated in the prompt at the bottom of the console. 
2. Create a file main.tf containing (filling in values for tenancy_id and user_email):
    ```
   module "lacework_oci_cfg_integration" {
   source = "lacework/config/oci"
   create = true
   tenancy_id = "<tenancy_ocid>"
   user_email = "<user_email>"
   }
   ```

3. Install the Lacework CLI using the following command. Note that, in the OCI cloud shell, you must specify the install location explicitly, as follows: 
   ```
   curl https://raw.githubusercontent.com/lacework/go-sdk/main/cli/install.sh | bash -s -- -d /home/oci/bin
   ```
4. Configure the Lacework CLI with your API key. For details, see the [Create API Key](https://docs.lacework.net/cli/#create-api-key) and [Configure the CLI](https://docs.lacework.net/cli/#configure-the-cli) in the Lacework CLI documentation. 

Next, run Terraform and create the Lacework integration, as described in the next section.

## Running Terraform

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
4. List integrations to verify:
   ```
   lacework cloud-accounts list -t OciCfg
   ```

:::note
You may need to use the `--profile` option for the preceding Lacework CLI command, depending on your configuration. The default profile is used if you do not specify one. See [information on managing profiles](https://docs.lacework.net/cli#multiple-profiles) in the Lacework CLI documentation for more information.
:::
