## Lacework OCI Integration

Before using this terraform in here you must create the require environment variables to access your oci tenant. The recommended way to do this is:

1. Chane directory to the `terraform` folder and copy the `vars.tfvars.example` to `terraform.tfvars`
2. Update the values in this file to align with your administrative oci user access
```
region="<YOUR HOME REGION  (e.g. us-ashburn-1)>"
tenancy_ocid="<YOUR OCI TEANCY OCID>"
user_ocid="<YOUR OCI USER OCID>"
fingerprint="<YOUR KEY FINGER PRINT>"
private_key_path="<YOUR KEY KEY PATH (e.g. ~/.oci/myocikey.pem)>"

```
3. Once the file is updated run the following command to initialize terraform
`terraform init`
4. Now test the terraform using this command:
```
terraform plan
```
5. If everything look good apply the change using the following command:
```
terraform apply -auto-approve
```
6. After the plan is applied a lacework cloud account policy is created locally under ~/.oci/lacework_cloud_account.json. This file can be posted to lacework via the lacework cli to create your integration:

```
 lacework api post /api/v2/CloudAccounts -d "$(cat ~/.oci/lacework_cloud_account.json)"
```


| Note          |
|:---------------------------|
| You may need to use the `--profile` option for the lacework-cli depending on your configuration. The default profile will be used if one is not specified.     |