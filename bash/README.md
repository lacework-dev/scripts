# Handy BASH scrips for working with Lacework

## lw_aws_inventory.sh
Script for estimating license vCPUs in an AWS environment. It leverages the AWS CLI and leverages by default the default profile that’s either configured using environment variables or configuration files in the ~/.aws folder. The script provides output in a CSV format to be imported into a spreadsheet, as well as an easy-to-read summary.

Note the following about the script:
* It requires AWS CLI v2 to run
* It does not work on Windows
* It has only been verified to work on Mac and Linux based systems
* It works great in a cloud shell

The output from running the script can look as follows:
```
./lw_aws_inventory.sh -p admin-account -o -r us-east-1
Profile, Account ID, Regions, EC2 Instances, EC2 vCPUs, ECS Fargate Clusters, ECS Fargate Running Containers/Tasks, ECS Fargate CPU Units, ECS Fargate License vCPUs, Lambda Functions, MB Lambda Memory, Lambda License vCPUs, Total vCPUSs
sandbox-1, 123456789012, us-east-1, 2, 2, 0, 0, 0, 0, 0, 0, 0, 2
sandbox-2, 234567890123, us-east-1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
logging, 345678901234, us-east-1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
######################################################################
Lacework inventory collection complete.

Organizations Analyzed: 1
Accounts Analyzed:      3

EC2 Information
====================
EC2 Instances:     2
EC2 vCPUs:         2

Fargate Information
====================
ECS Clusters:                    0
ECS Fargate Running Tasks:       0
ECS Fargate Container CPU Units: 0
ECS Fargate vCPUs:               0

Lambda Information
====================
Lambda Functions:     0
MB Lambda Memory:     0
Lambda License vCPUs: 0

License Summary
====================
  EC2 vCPUs:            2
+ ECS Fargate vCPUs:    0
+ Lambda License vCPUs: 0
----------------------------
= Total vCPUs:          2
```
The following options can be used to modify how the script is run:
### Specify one or more account profiles to scan using -p parameter
```
./lw_aws_inventory.sh -p default,lw-customerdemo
```
### Specify what regions to scan, to speed up scanning or avoid restricted regions
```
./lw_aws_inventory.sh -r us-east-1,us-east-2
```
### Scan all accounts in an AWS Organization
```
./lw_aws_inventory.sh -o
```
This will leverage the OrganizationAccountAccessRole to scan all accounts in an organization.

## lw_gcp_inventory.sh
Script for estimating license vCPUs in a GCP environment, based on folder, project or organization level. 

Note the following about the script:
* It does not work on Windows
* It has only been verified to work on Mac and Linux based systems
* It works great in a cloud shell

```
$ ./lw_gcp_inventory.sh -help
Usage: ./lw_gcp_inventory.sh [-f folder] [-o organization] [-p project]
Any single scope can have multiple values comma delimited, but multiple scopes cannot be defined.
```

By default, the script will scan any project that the user has access to:
```
$ ./lw_gcp_inventory.sh
"Project", "VM Count", "vCPUs"
"projects/project-one", 2, 8
"projects/project-two", 3, 12
##########################################
Lacework inventory collection complete.

License Summary:
================================================
Number of VMs, including standard GKE: 5
vCPUs:                                 20
```

The scope of the scan can be further refined using the -f, -o or -p parameters:
```
$ ./lw_gcp_inventory.sh -p project-one,project-two
"Project", "VM Count", "vCPUs"
"projects/project-one", 2, 8
"projects/project-two", 3, 12
##########################################
Lacework inventory collection complete.

License Summary:
================================================
Number of VMs, including standard GKE: 5
vCPUs:                                 20
```

## lw_azure_inventory.sh
Script for estimating license vCPUs in an Azure environment, based on folder, project or organization level. 

Note the following about the script:
* It does not work on Windows
* It has only been verified to work on Mac and Linux based systems
* It works great in a cloud shell

```
./lw_azure_inventory.sh -help
Usage: ./lw_azure_inventory.sh [-m management_group] [-s subscription]
Any single scope can have multiple values comma delimited, but multiple scopes cannot be defined.
```

By default, the script will scan any subscriptions the user has configured access to:
```
$ ./lw_azure_inventory.sh -m b448f327-c977-4cb8-9c27-09cfaa781bb9
resource-graph extension already present...
Building Azure VM SKU to vCPU map...
Map built successfully.
Load subscriptions
Load VMs
Load VMSS
"Subscription ID", "Subscription Name", "VM Instances", "VM vCPUs", "VM Scale Sets", "VM Scale Set Instances", "VM Scale Set vCPUs", "Total Subscription vCPUs"
"1215ba55...", "Subscription Number One", 2, 4, 0, 0, 0, 4
"72165fcf...", "Subscription Number Two", 1, 2, 0, 0, 0, 2
##########################################
Lacework inventory collection complete.

VM Summary:
===============================
VM Instances:     3
VM vCPUS:         6

VM Scale Set Summary:
===============================
VM Scale Sets:          0
VM Scale Set Instances: 0
VM Scale Set vCPUs:     0

License Summary
===============================
  VM vCPUS:             6
+ VM Scale Set vCPUs:   0
-------------------------------
Total vCPUs:            6
```

The scope can further be refined by specifying management groups or subscriptions.
### Specify subscriptions to scan
```
$ ./lw_azure_inventory.sh -s 1215ba55,72165fcf
```
### Specify management group to scan
```
$ ./lw_azure_inventory.sh -m mymanagementgroup,myothermanagementgroup
```
