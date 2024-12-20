import json
import subprocess
import requests
import sys

def execute_lacework_command(command):
    result = subprocess.run(command, shell=True, capture_output=True, text=True)
    if result.returncode != 0:
        raise Exception(f"Error executing lacework command: {result.stderr}")
    return json.loads(result.stdout)

def fetch_all_data_lacework(initial_data):
    combined_data = initial_data['data']
    next_page_url = initial_data.get('paging', {}).get('urls', {}).get('nextPage')

    while next_page_url:
        next_page_path = next_page_url.split('/api/v2/Configs/ComplianceEvaluations/')[1]
        next_page_command = f'lacework --nocache --debug api get /api/v2/Configs/ComplianceEvaluations/{next_page_path} --profile=dev8'

        response_data = execute_lacework_command(next_page_command)
        combined_data.extend(response_data['data'])
        next_page_url = response_data.get('paging', {}).get('urls', {}).get('nextPage')

    return combined_data

def get_bearer_token(x_lw_uaks):
    auth_url = 'http://localhost:8890/api/v2/access/tokens'
    headers = {
        'X-Lw-Uaks': x_lw_uaks,
        'Content-Type': 'application/json'
    }
    data = {
        "keyId": "DEV81383_89F73ADAADCE8A85746038C4D83F738DA1D2ADAC7CB7298",
        "expiryTime": 3600
    }
    response = requests.post(auth_url, headers=headers, json=data)
    response.raise_for_status()
    return response.json()['token']

def fetch_all_data_curl(initial_data, bearer_token):
    combined_data = initial_data['data']
    next_page_url = initial_data.get('paging', {}).get('urls', {}).get('nextPage')

    while next_page_url:
        next_page_path = next_page_url.split('/api/v2/Configs/ComplianceEvaluations/')[1]
        next_page_url = f'http://localhost:8890/api/v2/Configs/ComplianceEvaluations/{next_page_path}'
        headers = {
            'Authorization': f'Bearer {bearer_token}',
            'Content-Type': 'application/json'
        }
        response = requests.get(next_page_url, headers=headers)
        response.raise_for_status()
        response_data = response.json()
        combined_data.extend(response_data['data'])
        next_page_url = response_data.get('paging', {}).get('urls', {}).get('nextPage')

    return combined_data

def main(method, x_lw_uaks):
    if method == 'lacework':
        initial_command = '''lacework --nocache --debug api post /api/v2/Configs/ComplianceEvaluations/search -d '{
            "timeFilter": {
                    "startTime": "2024-12-01T08:04:28.684Z",
                    "endTime": "2024-12-01T12:04:29.684Z"
            },
            "dataset": "AwsCompliance"
        }' --profile=dev8 | jq .'''
        initial_data = execute_lacework_command(initial_command)
        combined_data = fetch_all_data_lacework(initial_data)
    elif method == 'curl':
        bearer_token = get_bearer_token(x_lw_uaks)
        initial_url = 'http://localhost:8890/api/v2/Configs/ComplianceEvaluations/search'
        headers = {
            'Authorization': f'Bearer {bearer_token}',
            'Content-Type': 'application/json'
        }
        data = {
            "timeFilter": {
                "startTime": "2024-12-01T08:04:28.684Z",
                "endTime": "2024-12-01T12:04:29.684Z"
            },
            "dataset": "AwsCompliance"
        }
        response = requests.post(initial_url, headers=headers, json=data)
        response.raise_for_status()
        initial_data = response.json()
        combined_data = fetch_all_data_curl(initial_data, bearer_token)
    else:
        raise ValueError("Invalid method. Use 'lacework' or 'curl'.")

    with open('combined_data.json', 'w') as f:
        json.dump(combined_data, f, indent=4)

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python script.py <method> <X-Lw-Uaks>")
    else:
        main(method=sys.argv[1], x_lw_uaks=sys.argv[2])
