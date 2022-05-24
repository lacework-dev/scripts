# Inventory and Exploits Scripts
## Inventory Scripts
The inventory scripts contained with this directory report the number of cloud resources in use within a cloud provider environment.

### AWS Inventory Script
#### Prerequisites
The following tools are required in order to run the [AWS Inventory Script](./lw_aws_inventory.sh):
- `awscli`
- `jq`
#### Permissions Required
The following permissions are required to run the [AWS Inventory Script](./lw_aws_inventory.sh):


```
ec2:DescribeRegions
ec2:DescribeNatGateways
ec2:DescribeInstances
ecs:ListClusters
elb:DescribeLoadBalancers
elbv2:DescribeLoadBalancer
fargate:DescribeTasks
rds:DescribeDbInstances
redshift:DescribeClusters
sts:GetCallerIdentity
```

#### Basic Usage
To execute the script with the default parameters, you may run the following commands:
```
curl -O https://raw.githubusercontent.com/lacework-dev/scripts/main/bash/lw_aws_inventory.sh
chmod +x lw_aws_inventory.sh
./lw_aws_inventory.sh
```

### Azure Inventory Script
#### Prerequisites
The following tools are required in order to run the [Azure Inventory Script](./lw_azure_inventory.sh):

- `az`
- `jq`

#### Permissions Required
The following commands will be executed as part of the [Azure Inventory Script](./lw_azure_inventory.sh):

```
az account list
az account set
az group list
az network lb list
az network vnet-gateway list
az sql server list
az vm list
az vmss list
```
#### Basic Usage
To execute the script with the default parameters, you may run the following commands:
```
curl -O https://raw.githubusercontent.com/lacework-dev/scripts/main/bash/lw_azure_inventory.sh
chmod +x lw_azure_inventory.sh
./lw_azure_inventory.sh
```
### GCP Inventory Script
#### Prerequisites
The following tools are required in order to run the [GCP Inventory Script](./lw_gcp_inventory.sh):
- `gcloud`
- `jq`
#### Permissions Required
The following commands will be executed as part of the [GCP Inventory Script](./lw_gcp_inventory.sh):

```
gcloud compute forwarding-rules lis
gcloud compute instances list
gcloud compute routers list
gcloud projects list
gcloud services list
gcloud sql instances list
```
#### Basic Usage
To execute the script with the default parameters, you may run the following commands:
```
curl -O https://raw.githubusercontent.com/lacework-dev/scripts/main/bash/lw_gcp_inventory.sh
chmod +x lw_gcp_inventory.sh
./lw_gcp_inventory.sh
```
## Exploit Scripts
TBD