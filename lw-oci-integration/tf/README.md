## Lacework OCI Integration

The terraform scripts may be run locally or via an OCI cloud shell.
We recommend the OCI cloud shell, since it comes with terraform pre-installed and authentication is provisioned.

## Prepare to run terraform locally (Option 1)

Before using the Terraform script you must create the required environment variables to access your OCI tenant. The recommended way to do this is:

1. clone this github repo
For example:
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

4. Install lacework cli (if it is not already) and configure with API KEY.
See guide here: https://docs.lacework.net/cli/

## Prepare to run terraform via OCI Cloud Shell (Option 2)

1. Open OCI cloud shell
```
For example:
(a) Logon to OCI console
(b) Click on the '<>' icon (developer tools), located in top right of OCI web console. 
(c) Select Cloud Shell.
```

2. clone this github repo
For example:
```
git clone https://github.com/lacework-dev/scripts.git
```

3. Change directory to the `lw-oci-integration/tf` folder and copy the `vars.tfvars.example` to `terraform.tfvars`.

4. OCI auth is automatically handled by the cloud shell. To use this, we modify a couple of files:

```
(a) main.tf

Edit the file so the provider section looks like this (set tenancy_ocid and region accordingly):

provider "oci" {
  tenancy_ocid = "ocid1.tenancy.oc1..aaaaaaaatxph3zpu3jkem4cseejktwllb6dgsam7cx3jy63pazejzobvjqqq"
  region = "us-sanjose-1"
}

```

```
(b) terraform.tfvars

Set region and tenancy_ocid as appropriate. user_ocid, fingerprint 
and private_key_path are not applicable when using cloud shell.
group_name, user_name and policy_name will be
created by the terraform script for the Lacework OCI integration. 
They can be left as they are, or modified if required.

region="us-sanjose-1"
tenancy_ocid="ocid1.tenancy.oc1..aaaaaaaatxph3zpu3jkem4cseejktwllb6dgsam7cx3jy63pazejzobvjqia"
user_ocid="NotApplicable"
fingerprint="NotApplicable"
private_key_path="NotApplicable"

group_name="lacework_group_security_audit"
user_name="lacework_user_security_audit"
policy_name="lacework_policy_security_audit"

```

5. Install lacework cli (if it is not already) and configure with API KEY.
      See guide here: https://docs.lacework.net/cli/

Note:The step to install the cli may fail with permission denied on the OCI cloud shell. If this happens, follow these steps:

(a) Download the install script
```
curl https://raw.githubusercontent.com/lacework/go-sdk/main/cli/install.sh
```
(b) Install to the present working directory (PWD):
```
./install.sh -d $PWD
```
(c) Modify the path (temporary) to include the PWD:
```
export PATH=$PATH:$PWD
```

Now, continue following instructions on linked page to configure with API KEY.

# Running Terraform (common to option 1 + 2)

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


| Note          |
|:---------------------------|
| You may need to use the `--profile` option for the lacework-cli depending on your configuration. The default profile will be used if one is not specified.     |
