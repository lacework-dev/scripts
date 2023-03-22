# Instance Discovery 

## Identify Instances without Lacework Agent

A script to review current Lacework instance inventories against active agents to help identify hosts lacking the Lacework agent.

Supports GCP & AWS. Azure VM support present, but not comprehensive for VMSS. Initial Fargate support just introduced. 

## How to Run

`docker run -v ~/.lacework.toml:/home/user/.lacework.toml valerianjone807/instance-discovery --json`
`docker run -v ~/.lacework.toml:/home/user/.lacework.toml valerianjone807/instance-discovery --csv --profile <lacework profile> > whitespace-report.csv`

``` python
pip install -r requirements.txt
python3 instances_without_agents.py --json
```

## Results

There are three separate result sets:
- Instances without Agents -- These are resources which we have in Resource Inventory which could not be reconciled with agents reporting in. 
- Agents without Inventory -- These are agents which are reporting in, but for which we do not have an inventory record of the instance. This could be due to inventory staleness or from agents running on uncovered Cloud Accounts or on-prem VMs.
- Instances with Agents -- These are the inventory records which correctly reconcile with agent info. 

Note: As we don't currently inventory Fargate tasks, these will always show as "Agents without Inventory"


## Arguments

| short | long                              | default | help                                                                                                                                                                             |
| :---- | :-------------------------------- | :------ | :--------------------------------------------------------------------------------------------|
| `-h`  | `--help`                          |         | show this help message and exit                                                                                                                                                 |
|       | `--account`                       | `None`  | The Lacework account to use                                                                  |
|       | `--subaccount`                    | `None`  | The Lacework sub-account to use                                                                                                                                                  |
|       | `--api-key`                       | `None`  | The Lacework API key to use                                                                  |
|       | `--api-secret`                    | `None`  | The Lacework API secret to use                                                                                                                                                  |
| `-p`  | `--profile`                       | `None`  | The Lacework CLI profile to use                                                                                                                                                  |
|       | `--current-sub-account-only`      | `False` | Default behavior will iterate all Lacework sub-subaccounts                                   |
|       | `--statistics`                    | `False` | When selected, output will be deployment statistics will be provided instead of output results |
|       | `--csv`                           | `False` | Enable csv output                                                                            |
|       | `--json`                          | `False` | Enable json output      
|       | `--debug`                         | `False` | Enable debug logging                                                                         |
