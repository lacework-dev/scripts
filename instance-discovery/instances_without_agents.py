import json
import argparse
import logging
import os
import copy

from datetime import datetime, timedelta, timezone
from laceworksdk import LaceworkClient
from concurrent.futures import ThreadPoolExecutor, as_completed

logger = logging.getLogger('instance-discovery')

MAX_RESULT_SET: int = 500_000
LOOKBACK_DAYS: int = 1
INVENTORY_CACHE: dict = {}
AGENT_CACHE: dict = {}
INSTANCE_CLUSTER_CACHE: dict = {}


class OutputRecord():
    def __init__(self, urn: str, creation_time: str, is_kubernetes: bool, subaccount: str, os_image: str, tags: object = None) -> None:
        self.urn = urn
        self.creation_time = creation_time
        self.is_kubernetes = is_kubernetes
        self.os_image = os_image
        self.subaccount = subaccount
        self.tags = tags
    
    def __str__(self) -> str:
        return json.dumps(self.__dict__, indent=4, sort_keys=True)

    def __repr__(self) -> str:
        return json.dumps(self.__dict__, indent=4, sort_keys=True)
    
    def __eq__(self, o: object) -> bool:
        return self.urn == o.urn

    def __hash__(self) -> int:
        return hash(self.urn)


class InstanceResult():
    def __init__(self, instances_without_agents: set[OutputRecord], instances_with_agents: set[OutputRecord], agents_without_inventory: set[OutputRecord]) -> None:
        self.instances_without_agents = list(instances_without_agents)
        self.instances_with_agents = list(instances_with_agents)
        self.agents_without_inventory = list(agents_without_inventory)

        self.instances_without_agents.sort(key=lambda x: x.urn)
        self.instances_with_agents.sort(key=lambda x: x.urn)
        self.agents_without_inventory.sort(key=lambda x: x.urn)

    def printJson(self) -> None:
        print(json.dumps(self.__dict__, indent=4, sort_keys=True, default=serialize))

    def printCsv(self) -> None:
        print("Identifier,CreationTime,Instance_without_agent,Instance_reconciled_with_agent,Agent_without_inventory,Os_image,Tags,Subaccount")
        for i in self.instances_without_agents:
            print(f'{i.urn},{i.creation_time},true,,,"{i.os_image}","{str(i.tags).replace(chr(34),chr(39))}",{i.subaccount}')

        for i in self.instances_with_agents:
            print(f'{i.urn},{i.creation_time},,true,,"{i.os_image}","{str(i.tags).replace(chr(34),chr(39))}",{i.subaccount}')

        for i in self.agents_without_inventory:
            print(f'{i.urn},{i.creation_time},,,true,"{i.os_image}","{str(i.tags).replace(chr(34),chr(39))}",{i.subaccount}')

    def printStandard(self) -> None:
        if len(self.instances_without_agents) > 0:
            print(f'Instances without agent:')
            for instance in self.instances_without_agents:
                print(f'\t{instance.urn}')
            print('\n')

        if len(self.instances_with_agents) > 0:
            print(f'Instances reconciled with agent:')
            for instance in self.instances_with_agents:
                print(f'\t{instance.urn}')
            print('\n')

        if len(self.agents_without_inventory) > 0:
            print(f'Agents without corresponding inventory:')
            for instance in self.agents_without_inventory:
                print(f'\t{instance.urn}')
            print('\n')


def serialize(obj: object) -> dict:
    """JSON serializer for objects not serializable by default json code"""
    return obj.__dict__


def get_all_tenant_subaccounts(client: LaceworkClient) -> list:
    return [i['accountName'] for i in client.user_profile.get()['data'][0]['accounts']]


def check_truncation(results: list) -> bool:
    if type(results) == list:
        if len(results) >= MAX_RESULT_SET:
            return True
    return False


# inspect resource to determine if it matches known identifiers marking it as a k8s node
def is_kubernetes(resource: dict, identifier: str) -> bool:
    if identifier == "Aws":
        if 'Tags' in resource['resourceConfig']:
            for t in resource['resourceConfig']['Tags']:
                if t['Key'] == 'eks:cluster-name':
                    INSTANCE_CLUSTER_CACHE[resource['resourceConfig']['InstanceId']] = t['Value']
                    return True
    elif identifier == "Gcp":
        if 'labels' in resource['resourceConfig']:
            for l in resource['resourceConfig']['labels']:
                if 'goog-gke-node' in l:
                    # TODO: INSTANCE_CLUSTER_CACHE
                    return True
    elif identifier == "Azure":
        pass
    else:
        raise Exception("Identifer not correctly passed to is_kubernetes!")

    return False


def get_fargate_with_lacework_agents(input: object, lw_subaccount: str) -> tuple[list, list]:
    tasks_with_agent = list()
    tasks_without_agent = list()

    for page in input:
        for task in page['data']:
            task_placed = False
            tags = task['resourceConfig']['tags'] if 'tags' in task['resourceConfig'] else ''
            if 'containers' in task['resourceConfig']:
                for container in task['resourceConfig']['containers']:
                    if 'datacollector' in container['image']:
                        tasks_with_agent.append(OutputRecord(container['taskArn'],'',False, lw_subaccount, '', tags))
                        task_placed = True
                        break
                if not task_placed:
                    tasks_without_agent.append(OutputRecord(task['resourceConfig']['taskArn'],'',False, lw_subaccount, '', tags))
                
    return (tasks_with_agent, tasks_without_agent)


def apply_fargate_filter(client: LaceworkClient, start_time: str, end_time: str, instances_without_agents: list, matched_instances: list, agents_without_inventory: list, lw_subaccount_name: str) -> tuple[list, list, list]:

    ##########
    # Fargate is different
    ##########
    fargate_inventory = client.inventory.search(json={
            'timeFilter': { 
                'startTime' : start_time, 
                'endTime'   : end_time
            }, 
            'filters': [
                { 'field': 'resourceType', 'expression': 'eq', 'value':'ecs:task'},
                { 'field': 'resourceConfig.launchType', 'expression': 'eq', 'value':'FARGATE'}
            ],
            'csp': 'AWS'
        })

    # TODO: type the task
    fargate_tasks_with_agent, fargate_tasks_without_agent = get_fargate_with_lacework_agents(fargate_inventory, lw_subaccount_name)

    # Fargate complications -- Currently going to run this as a completely seperate filter
    # and modify the three existing result sets independently

    matched_fargate_instances = set([task for task in fargate_tasks_with_agent if any(task.urn in hostname.urn for hostname in agents_without_inventory)])
    matched_instances.extend(matched_fargate_instances)
    logger.debug(f'matched faragate instances: {len(matched_instances)}')
    logger.debug(f'missing fargate instances: {len(fargate_tasks_without_agent)}')

    # The rfind is likely not comprehensive, but it nails it for the sample data
    # so in the spirit of getting something out there...away we go
    logger.debug(f'agents w/o inventory - pre: {len(agents_without_inventory)}')
    set_matched_fargate_urns = set([t.urn for t in matched_fargate_instances])
    agents_without_inventory = [a for a in agents_without_inventory if a.urn[0:a.urn.rfind('_')] not in set_matched_fargate_urns]
    logger.debug(f'agents w/o inventory - post: {len(agents_without_inventory)}')

    logger.debug(f'instances w/o agents - pre: {len(instances_without_agents)}')
    instances_without_agents.extend(fargate_tasks_without_agent)
    logger.debug(f'instances w/o agents - post: {len(instances_without_agents)}')

    return (instances_without_agents, matched_instances, agents_without_inventory)


def get_agent_instances(client: LaceworkClient, start_time: str, end_time: str) -> list[dict]:

    ########
    # Agents
    ########
    all_agent_instances = client.agent_info.search(json={
            'timeFilter': { 
                'startTime' : start_time, 
                'endTime'   : end_time
            } 
        })

    list_agent_instances = list()
    for page in all_agent_instances:
        for r in page['data']:
            if ('tags' in r.keys() 
                    and 'VmProvider' in r['tags'].keys() 
                    and (r['tags']['VmProvider'] == 'GCE' or r['tags']['VmProvider'] == 'GCP')):
                
                list_agent_instances.append(r['tags']['InstanceId'])
                try:
                    AGENT_CACHE[r['tags']['InstanceId']] = 'gcp' + '/' + r['tags']['ProjectId'] + '/' + r['tags']['Hostname']
                except:
                    AGENT_CACHE[r['tags']['InstanceId']] = 'gcp' + '/' + r['tags']['Hostname']

            elif ('tags' in r.keys() 
                    and 'VmProvider' in r['tags'].keys() 
                    and r['tags']['VmProvider'] == 'AWS'):

                if 'InstanceId' in r['tags'].keys(): # EC2 use case - InstanceId is in URN
                    list_agent_instances.append(r['tags']['InstanceId'])
                    if 'Account' in r['tags'].keys():
                        AGENT_CACHE[r['tags']['InstanceId']] = 'aws' + '/' + r['tags']['Account'] + '/' + r['tags']['Hostname']
                    else: # random Windows agent use case?
                        AGENT_CACHE[r['tags']['InstanceId']] = 'aws' + '/' + r['tags']['ProjectId'] + '/' + r['tags']['Hostname']
                else: # Fargate use case 
                    list_agent_instances.append(r['tags']['Hostname'])

            elif ('tags' in r.keys() 
                    and 'VmProvider' in r['tags'].keys() 
                    and r['tags']['VmProvider'] == 'Microsoft.Compute'):

                list_agent_instances.append(r['tags']['InstanceId'])
                if 'Account' in r['tags'].keys():
                    AGENT_CACHE[r['tags']['InstanceId']] = 'azure' + '/' + r['tags']['Account'] + '/' + r['tags']['Hostname']
                else: # random Windows agent use case?
                    AGENT_CACHE[r['tags']['InstanceId']] = 'azure' + '/' + r['tags']['ProjectId'] + '/' + r['tags']['Hostname']

            else:
                list_agent_instances.append(r['hostname'])
    
    if check_truncation(list_agent_instances):
        logger.warning(f'WARNING: Agent Instances truncated at {MAX_RESULT_SET} records')
    logger.debug(f'Agent Instances: {list_agent_instances}\n')

    return list_agent_instances


def get_gcp_instance_inventory(client: LaceworkClient, start_time: str, end_time: str, lw_subaccount: str) -> list[dict]:
    ######
    # GCP
    ######
    gcp_inventory = client.inventory.search(json={
            'timeFilter': { 
                'startTime' : start_time, 
                'endTime'   : end_time
            }, 
            'filters': [
                { 'field': 'resourceType', 'expression': 'eq', 'value':'compute.googleapis.com/Instance'}
            ],
            'csp': 'GCP'
        })

    list_gcp_instances = list()
    for page in gcp_inventory:
        for r in page.get('data', []):
            # rough handling so that a small number of unexpected formats don't kill the entire output
                try:
                    tags = r['resourceConfig']['tags'] if 'tags' in r['resourceConfig'] else ''
                    identifier = r['resourceConfig']['id']
                    list_gcp_instances.append(identifier)
                    # identify OS image from GCP instance
                    os_image = str()
                    try:
                        count = 0
                        for disk in r['resourceConfig']['disks']:
                            if 'licenses' in disk.keys():
                                os_image = r['resourceConfig']['disks'][count]['licenses']
                                break
                            elif 'initializeParams' in disk.keys():
                                params = r['resourceConfig']['disks']['initializeParams'] 
                                if 'sourceImage' in params:
                                    os_image = r['resourceConfig']['disks']['initializeParams']['sourceImage']
                                    break
                            count += 1
                    except:
                        if r['resourceConfig']['status'] != 'TERMINATED':
                            logger.warning(f'Unable to parse os_image info for instance {r}')

                    INVENTORY_CACHE[identifier] = OutputRecord(r['urn'], r['resourceConfig']['creationTimestamp'], is_kubernetes(r,'Gcp'), lw_subaccount, os_image, tags)
                except Exception as ex:
                    logger.warning(f'Host could not be parsed due to incomplete inventory information: {ex} \n{r}')
                    pass

    if check_truncation(list_gcp_instances):
        logger.warning(f'WARNING: GCP Instances truncated at {MAX_RESULT_SET} records')
    logger.debug(f'GCP Instances: {list_gcp_instances}\n')

    return list_gcp_instances


def get_aws_instance_inventory(client: LaceworkClient, start_time: str, end_time: str, lw_subaccount: str) -> list[dict]:
    ######
    # AWS
    ######
    aws_inventory = client.inventory.search(json={
            'timeFilter': { 
                'startTime' : start_time, 
                'endTime'   : end_time
            }, 
            'filters': [
                { 'field': 'resourceType', 'expression': 'eq', 'value':'ec2:instance'}
            ],
            'csp': 'AWS'
        })

    list_aws_instances = list()
    for page in aws_inventory:
        for r in page.get('data', []):
            # rough handling so that a small number of unexpected formats don't kill the entire output
            try:
                identifier = r['resourceConfig']['InstanceId']
                tags = r['resourceConfig']['Tags'] if 'Tags' in r['resourceConfig'] else ''
                list_aws_instances.append(identifier)
                os_image = str()
                INVENTORY_CACHE[identifier] = OutputRecord(r['urn'],  r['resourceConfig']['LaunchTime'], is_kubernetes(r,'Aws'), lw_subaccount, os_image, tags)
            except Exception as ex:
                logger.warning(f'Host could not be parsed due to incomplete inventory information: {ex} \n{r}')
                pass

    if check_truncation(list_aws_instances):
        logger.warning(f'WARNING: AWS Instances truncated at {MAX_RESULT_SET} records')
    logger.debug(f'AWS Instances: {list_aws_instances}\n')
    
    return list_aws_instances


def get_azure_instance_inventory(client: LaceworkClient, start_time: str, end_time: str, lw_subaccount: str) -> list[dict]:
    ######
    # Azure
    ######
    # TODO: Get VMSS instances
    azure_inventory = client.inventory.search(json={
            'timeFilter': { 
                'startTime' : start_time, 
                'endTime'   : end_time
            }, 
            'filters': [
                { 'field': 'resourceType', 'expression': 'eq', 'value':'microsoft.compute/virtualmachines'}
            ],
            'csp': 'Azure'
        })

    list_azure_instances = list()
    for page in azure_inventory:
        for r in page.get('data', []):
            # rough handling so that a small number of unexpected formats don't kill the entire output
            try:
                tags = r['resourceTags'] if 'resourceTags' in r else ''
                identifier = r['resourceConfig']['vmId']
                list_azure_instances.append(identifier)
                os_image = str()
                INVENTORY_CACHE[identifier] = OutputRecord(r['urn'], r['resourceConfig']['timeCreated'], is_kubernetes(r,'Azure'), lw_subaccount, os_image, tags)
            except Exception as ex:
                logger.warning(f'Host could not be parsed due to incomplete inventory information: {ex} \n{r}')
                pass

    if check_truncation(list_azure_instances):
        logger.warning(f'WARNING: Azure Instances truncated at {MAX_RESULT_SET} records')
    logger.debug(f'Azure Instances: {list_azure_instances}\n')

    return list_azure_instances


def apply_agent_presence_filtering(instance_inventory: list, list_agent_instances: list, lw_subaccount: str) -> tuple[list, list, list]:

    instances_without_agents = list()
    matched_instances = list()
    agents_without_inventory = list()

    set_agent_instances = set(list_agent_instances)
    #########
    # Set Ops
    #########
    for instance_id in instance_inventory:
        normalized_output = INVENTORY_CACHE[instance_id]

        if instance_id in set_agent_instances:
            matched_instances.append(normalized_output)
            # TODO: add secondary check for "premptible instances"
        else:
            instances_without_agents.append(normalized_output)

    for instance in list_agent_instances:
        if not any(instance in instance_urn.urn for instance_urn in matched_instances):
            if instance in AGENT_CACHE:
                # pull out host name if we have it
                instance = AGENT_CACHE[instance]
            o = OutputRecord(instance,'','',lw_subaccount,'')
            agents_without_inventory.append(o)

    return (instances_without_agents, matched_instances, agents_without_inventory)


def generate_subaccount_report(client: LaceworkClient, start_time: str, end_time: str, lw_subaccount: str) -> tuple[list, list, list]:
    list_agent_instances = get_agent_instances(client, start_time, end_time)
    list_gcp_instances = get_gcp_instance_inventory(client, start_time, end_time, lw_subaccount)
    list_aws_instances = get_aws_instance_inventory(client, start_time, end_time, lw_subaccount)
    list_azure_instances = get_azure_instance_inventory(client, start_time, end_time, lw_subaccount)

    all_instances_inventory = set(list_aws_instances) | set(list_gcp_instances) | set(list_azure_instances) # union the three sets
    instances_without_agents, matched_instances, agents_without_inventory = apply_agent_presence_filtering(all_instances_inventory, list_agent_instances, lw_subaccount)

    logger.debug(f'Instances_without_agents:{instances_without_agents}')
    logger.debug(f'Matched_Instances:{matched_instances}')
    logger.debug(f'Agents_without_inventory:{agents_without_inventory}')

    # run the Fargate pass as a separate filter (for now)
    instances_without_agents, matched_instances, agents_without_inventory = apply_fargate_filter(client, start_time, end_time, instances_without_agents, matched_instances, agents_without_inventory, lw_subaccount)

    return (instances_without_agents, matched_instances, agents_without_inventory)


def output_statistics(args: argparse.Namespace, instance_result: InstanceResult, user_profile_data: dict) -> None:

    coverage_percent = round((len(instance_result.instances_with_agents) / len(instance_result.instances_without_agents + instance_result.instances_with_agents)) * 100, 2) if len(instance_result.instances_with_agents) > 0 else 0
    print(f'Number of distinct hosts identified during inventory assessment: {len(instance_result.instances_without_agents + instance_result.instances_with_agents)}')
    print(f'Number of hosts which report successful agent operation: {len(instance_result.instances_with_agents)}')
    print(f'Coverage Percentage: {coverage_percent}%')

    if not args.current_sub_account_only:
        for lw_subaccount in user_profile_data.get('accounts', []):
            lw_subaccount_name = lw_subaccount.get('accountName','')

            instances_without_agents_count = len([i for i in instance_result.instances_without_agents if i.subaccount == lw_subaccount_name])
            instances_with_agent_count = len([i for i in instance_result.instances_with_agents if i.subaccount == lw_subaccount_name])
            # divide by zero handler...
            coverage_percent = round((instances_with_agent_count / (instances_without_agents_count + instances_with_agent_count)) * 100, 2) if instances_with_agent_count > 0 else 0

            print()
            print(f'{lw_subaccount_name} -- Number of distinct hosts identified during inventory assessment: {instances_without_agents_count + instances_with_agent_count}')
            print(f'{lw_subaccount_name} -- Number of hosts which report successful agent operation: {instances_with_agent_count}')
            print(f'{lw_subaccount_name} -- Coverage Percentage: {coverage_percent}%')


def main(args: argparse.Namespace) -> None:

    if not args.profile and not args.account and not args.subaccount and not args.api_key and not args.api_secret:
        args.profile = 'default'

    if args.csv and args.json:
        logger.error('Please specify only one of --csv or --json for output formatting')
        exit(1)
    elif args.profile and any([args.account, args.api_key, args.api_secret]):
        logger.error('If passing a profile, other credential values should not be specified.')
        exit(1)
    elif not args.profile and not all([args.account, args.api_key, args.api_secret]):
        logger.error('If passing credentials, please specify at least --account, --api-key, and --api-secret. --sub-account is optional for this input format.')
        exit(1)

    # setup logger in main for testability
    logging.basicConfig(
        format='%(asctime)s %(name)s [%(levelname)s] %(message)s'
    )
    logger = logging.getLogger('instance-discovery')
    logger.setLevel(os.getenv('LOG_LEVEL', logging.INFO))

    try:
        client = LaceworkClient(
            account=args.account,
            subaccount=args.subaccount,
            api_key=args.api_key,
            api_secret=args.api_secret,
            profile=args.profile
        )
    except Exception:
        raise

    if args.debug:
        logger.setLevel('DEBUG')
        logging.basicConfig(level=logging.DEBUG)

    current_time = datetime.now(timezone.utc)
    start_time = current_time - timedelta(days=LOOKBACK_DAYS)
    start_time = start_time.strftime('%Y-%m-%dT%H:%M:%SZ')
    end_time = current_time.strftime('%Y-%m-%dT%H:%M:%SZ')

    instances_without_agents = set()
    matched_instances = set()
    agents_without_inventory = set()

    # Grab the lacework accounts that the user has access to
    user_profile = client.user_profile.get()
    user_profile_data = user_profile.get("data", {})[0]

    if args.current_sub_account_only:
        # magic to get the current subaccount for reporting on where things are
        lw_subaccount = client.account._session.__dict__['_subaccount'] 
        if lw_subaccount == None:
            # very hacky pull of the subdomain off the base_url
            lw_subaccount = client.account._session.__dict__['_base_url'].split('.')[0].split(':')[1][2::]

        instances_without_agents, matched_instances, agents_without_inventory = generate_subaccount_report(client, start_time, end_time, lw_subaccount)

    else:

        executor_tasks = list()
        with ThreadPoolExecutor() as executor:

            # Iterate through all subaccounts
            for lw_subaccount in user_profile_data.get('accounts', []):
                lw_subaccount_name = lw_subaccount.get('accountName','')
                client.set_subaccount(lw_subaccount_name)

                executor_tasks.append(executor.submit(generate_subaccount_report, copy.deepcopy(client), start_time, end_time, lw_subaccount_name))

            for task in as_completed(executor_tasks):
                result = task.result()

                instances_without_agents = instances_without_agents.union(result[0])
                matched_instances = matched_instances.union(result[1])
                agents_without_inventory = agents_without_inventory.union(result[2])

    instance_result = InstanceResult(instances_without_agents, matched_instances, agents_without_inventory)
    if args.statistics:
        output_statistics(args, instance_result,user_profile_data)
    else:
        if args.json:
            instance_result.printJson()
        elif args.csv:
            instance_result.printCsv()
        else:
            instance_result.printStandard()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description='Discover hosts not running the Lacework agent'
    )
    parser.add_argument(
        '--account',
        default=os.environ.get('LW_ACCOUNT', None),
        help='The Lacework account to use'
    )
    parser.add_argument(
        '--subaccount',
        default=os.environ.get('LW_SUBACCOUNT', None),
        help='The Lacework sub-account to use'
    )
    parser.add_argument(
        '--api-key',
        dest='api_key',
        default=os.environ.get('LW_API_KEY', None),
        help='The Lacework API key to use'
    )
    parser.add_argument(
        '--api-secret',
        dest='api_secret',
        default=os.environ.get('LW_API_SECRET', None),
        help='The Lacework API secret to use'
    )
    parser.add_argument(
        '-p', '--profile',
        default=os.environ.get('LW_PROFILE', None),
        help='The Lacework CLI profile to use'
    )
    parser.add_argument(
        '--current-sub-account-only',
        default=False,
        action='store_true',
        help='Report results for only current sub-account. Default is to iterate all sub-accounts the user has read access to.'
    )
    parser.add_argument(
        '--json',
        default=False,
        action='store_true',
        help='Emit results as json for machine processing'
    )
    parser.add_argument(
        '--csv',
        default=False,
        action='store_true',
        help='Emit results as csv'
    )
    parser.add_argument(
        '--statistics',
        default=False,
        action='store_true',
        help='Output only statistics'
    )
    parser.add_argument(
        '--debug',
        action='store_true',
        default=os.environ.get('LW_DEBUG', False),
        help='Enable debug logging'
    )
    args = parser.parse_args()

    main(args)
