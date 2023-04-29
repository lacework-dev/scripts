## Lacework OCI Integration

Before using the Terraform script you must create the required environment variables to access your OCI tenant. The recommended way to do this is:

1. Change directory to the `terraform` folder and copy the `vars.tfvars.example` to `terraform.tfvars`.
2. Update the values in this file to align with your administrative OCI user access.
```
region="<YOUR HOME REGION  (e.g. us-ashburn-1)>"
tenancy_ocid="<YOUR OCI TEANCY OCID>"
user_ocid="<YOUR OCI USER OCID>"
fingerprint="<YOUR KEY FINGER PRINT>"
private_key_path="<YOUR KEY KEY PATH (e.g. ~/.oci/myocikey.pem)>"

```
3. Once the file is updated, run the following command to initialize Terraform:
`terraform init`
4. Now test the Terraform using this command:
```
terraform plan
```
5. If everything looks good, apply the change using the following command:
```
terraform apply -auto-approve
```
6. After the plan is applied, a Lacework cloud account policy is created locally under ~/.oci/lacework_cloud_account.json. You can post this file to Lacework via the Lacework CLI to create your integration:

```
 lacework api post /api/v2/CloudAccounts -d "$(cat ~/.oci/lacework_cloud_account.json)"
```


| Note          |
|:---------------------------|
| You may need to use the `--profile` option for the lacework-cli depending on your configuration. The default profile will be used if one is not specified.     |
