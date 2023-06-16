# scripts for integrating OCI to Lacework

## Introduction

* ```lacework_oci_integration_setup.sh```
Tested against identity-domain tenancy. For classic (IDCS) based OCI tenancy, we recommend following the manual steps and the helper script lacework_integration_payload.sh..
Script uses the OCI CLI to create the OCI service account, OCI group and policy. It then uses the lacework CLI to create the integration to Lacework.
Run script and provide values as prompted.

* ```lacework_integration_payload.sh``` only produces the JSON payload that can then be used to create the integration to Lacework using endpoint /api/v2/CloudAccounts
Please edit script before use to set the six variables appropriately. When executed, the script produces the payload in file ```lacework_payload.json```.
