# -*- coding: utf-8 -*-
"""
Example script to generate an IAM policy document containing observed IAM actions for a given IAM Role.
"""

import sys, os
import logging
import random
import json, csv
import re
import argparse

from datetime import datetime, timedelta, timezone
from dotenv import load_dotenv
from laceworksdk import LaceworkClient

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

load_dotenv()

def total_quantity(item):
    return sum(len(sublist) for sublist in item.values())

def split_dict(input_dict):
    group1 = {}
    group2 = {}
    total_group1 = 0
    total_group2 = 0
    
    for key, value in input_dict.items():
        if total_group1 <= total_group2:
            group1[key] = value
            total_group1 += total_quantity(value)
        else:
            group2[key] = value
            total_group2 += total_quantity(value)
    
    return [group1, group2]

def recursive_sort(data):
    if isinstance(data, dict):
        sorted_dict = {}
        for key, value in sorted(data.items()):
            sorted_dict[key] = recursive_sort(value)
        return sorted_dict
    elif isinstance(data, list):
        if len(data) > 0 and isinstance(data[0], dict):
            return sorted([recursive_sort(item) for item in data])
        else:
            return sorted(data)
    else:
        return data


def query_lacework(lacework_client, arn):
    logger.info('Querying for used entitlements for %s...' % arn)

    query_response = lacework_client.queries.execute(
        query_text = """{
            source { 
                LW_CE_ENTITLEMENTS
            }
            filter {
                PRINCIPAL_ID = '%s'
                and LAST_USED_TIME is not NULL
            }
            return distinct { 
                SERVICE,
                RESOURCE_ID,
                ACTION,
                LAST_USED_TIME
            }
        }""" % arn,
        arguments = dict(StartTimeRange=start_time, EndTimeRange=end_time)
    )

    if len(query_response['data']) == 0:
        logger.error("No records found for %s" % arn)
        sys.exit(1)

    logger.info("Found %i records" % len(query_response['data']))
    return query_response['data']

def parse_csv(filename):
    logger.info("Opening %s" % filename)
    if not os.path.exists(filename):
        logger.error(f"The file '{filename}' does not exist.")
        exit(1)
    csv_data = []
    with open(filename, 'r') as file:
        reader = csv.DictReader(file)
        for row in reader:
            if row['Used'] == '0:UNUSED':
                continue
            actions = json.loads(row['Actions'])
            for action in actions.keys():
                entry = {
                    'SERVICE': row['Service name'],
                    'RESOURCE_ID': row['Resource'],
                    'ACTION': action,
                }
                csv_data.append(entry)
    return csv_data

def generate_policies(data, max_chars, by_service=False):
    policies = []

    # call this function for each service to get a policy for each service
    if by_service:
        for service, resources in data.items():
            policies += generate_policies(data={service: resources}, max_chars=max_chars)
        return policies

    # initialize new policy doc
    working_iam_policy = {
        "Version": "2012-10-17",
        "Statement": []
    }
    working_data = {}
    
    # transform data into {resource_id: [actions]} 
    for service, resources in data.items():
        for resource_id, actions in resources.items():
            if resource_id not in working_data:
                working_data[resource_id] = []
            working_data[resource_id] += actions

    # create statements for each resource_id
    for resource_id, actions in working_data.items(): 
        statement = {
            "Sid": "Stmt" + str(random.randint(100000000, 999999999)),  # Generate random SID
            "Action": actions,
            "Effect": "Allow",
            "Resource": resource_id
        }
        working_iam_policy["Statement"].append(statement)

    # max_chars == 0 means user requested no splitting
    if max_chars == 0:
        policies.append(working_iam_policy)
        return policies

    # measure size of policy document, if too large, we need to split
    # logic is: first try to split on groups of services
    # if there is only one service, try to split on statements (resource_ids)
    # lastly split a statement into two by dividing on actions
    if len(json.dumps(working_iam_policy)) > max_chars:
        if len(data.keys()) > 1:
            logger.info('Policy document too large, splitting into groups of services')
            split_data = split_dict(data)
            for data in split_data:
                policies += generate_policies(data=data, max_chars=max_chars)
        else:
            # need to split service in half, either by separating statements into separate policies, or splitting actions list into two policies
            service = next(iter(data))
            resources = data[service]
            new_data = {}
            if len(resources.keys()) == 1:
                logger.info('List of actions for a single service is too large, splitting actions into multiple policies')
                resource_id = next(iter(resources))
                actions = resources[resource_id]
                split_idx = int(len(actions) / 2) + 1
                new_data[service+'-1'] = {resource_id: actions[0:split_idx+1]}
                new_data[service+'-2'] = {resource_id: actions[split_idx::]}
            else:
                logger.info('Too many actions for single service, attempting to split on resource id')
                for resource_id, actions in resources.items():
                    new_service = service+'-'+resource_id
                    new_data[new_service] = {resource_id: actions}
            
            policies += generate_policies(data=new_data, max_chars=max_chars)

    else:
        policies.append(working_iam_policy)
    return policies

if __name__ == "__main__":

    parser = argparse.ArgumentParser(description="Generate an IAM policy document containing observed IAM actions for a given IAM Role.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
generate-policy.py arn:aws:iam:123456::role/some-role
generate-policy.py arn:aws:iam:123456::role/some-role arn:aws:123456::role/some-other-role
generate-policy.py /path/to/some.csv /path/to/some-other.csv
generate-policy.py arn:aws:iam:123456::role/some-role --split=by-service
        """)
    parser.add_argument("--maxchars", type=int, help="Maximum size of a policy (does not count whitespace). Default is 6,000", default=6000)
    parser.add_argument("--split", type=str, help="How to handle splitting large datasets. Default is 'fewest-policies'", default='fewest-policies', choices=['fewest-policies', 'by-service', 'none'])
    parser.add_argument('sources', type=str, help="Specify sources. Can be local CSV files exported from Lacework, or a list of ARNs to fetch from the Lacework API", action='store', nargs='+')
    args = parser.parse_args()

    # Build start/end times
    current_time = datetime.now(timezone.utc)
    start_time = current_time - timedelta(days=1)
    start_time = start_time.strftime("%Y-%m-%dT%H:%M:%SZ")
    end_time = current_time.strftime("%Y-%m-%dT%H:%M:%SZ")

    # Start collecting raw data
    data = []
    lacework_client = None
    for source in args.sources:
        if re.match(r'^arn:aws:iam::\d*:.*$', source):
            # Instantiate a LaceworkClient instance
            if not lacework_client:
                lacework_client = LaceworkClient()
            data += query_lacework(lacework_client=lacework_client, arn=source)
        else:
            data += parse_csv(filename=source)

    logger.info("Generating policy document(s)")

    # Transform data into { service: { resource_id: [actions] } }
    # This helps us later when we need to assemble properly sized policy documents
    transformed_data = {}
    for entry in data:
        resource_id = entry["RESOURCE_ID"]
        action = entry["ACTION"]
        service = entry["SERVICE"]

        if service not in transformed_data:
            transformed_data[service] = {}
        if resource_id not in transformed_data[service]:
            transformed_data[service][resource_id] = [action]
        else:
            if action not in transformed_data[service][resource_id]:
                transformed_data[service][resource_id].append(action)
    
    transformed_data = recursive_sort(transformed_data)

    # Now run the recursive policy generation
    if args.split == 'fewest-policies':
        policies = generate_policies(data=transformed_data, max_chars=args.maxchars)
    elif args.split == 'by-service':
        policies = generate_policies(data=transformed_data, max_chars=args.maxchars, by_service=True)
    elif args.split == 'none':
        policies = generate_policies(data=transformed_data, max_chars=0)
    
    logger.info('Generated %i policy documents' % len(policies))
    print(json.dumps(policies, indent=2))
