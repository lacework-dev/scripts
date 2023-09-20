# scripts for integrating OCI to Lacework

## Introduction

* ```lacework_integration_payload.sh``` produces the JSON payload that can then be used to create the integration to Lacework using endpoint /api/v2/CloudAccounts. Intended to be used when a more manual or custom workflow is necessary.
Please edit script before use to set the six variables appropriately. When executed, the script produces the payload in file ```lacework_payload.json```.
