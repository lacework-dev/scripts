import json
import subprocess
import requests

def execute_lacework_command(command):
    result = subprocess.run(command, shell=True, capture_output=True, text=True)
    if result.returncode != 0:
        raise Exception(f"Error executing lacework command: {result.stderr}")
    return json.loads(result.stdout)

def fetch_all_data(initial_data):
    combined_data = initial_data['data']
    next_page_url = initial_data.get('paging', {}).get('urls', {}).get('nextPage')

    while next_page_url:
        # Remove the first section of the URL
        next_page_path = next_page_url.split('/api/v2/Configs/ComplianceEvaluations/')[1]
        next_page_command = f'lacework --nocache --debug api get /api/v2/Configs/ComplianceEvaluations/{next_page_path} --profile=dev8'
        
        response_data = execute_lacework_command(next_page_command)
        combined_data.extend(response_data['data'])
        next_page_url = response_data.get('paging', {}).get('urls', {}).get('nextPage')

    return combined_data

def main():
    initial_command = '''lacework --nocache --debug api post /api/v2/Configs/ComplianceEvaluations/search -d '{
        "timeFilter": {
                "startTime": "2024-12-01T08:04:28.684Z",
                "endTime": "2024-12-01T12:04:29.684Z"
        },
        "dataset": "AwsCompliance"
    }' --profile=dev8 | jq .'''
    
    initial_data = execute_lacework_command(initial_command)
    combined_data = fetch_all_data(initial_data)

    with open('combined_data.json', 'w') as f:
        json.dump(combined_data, f, indent=4)

if __name__ == "__main__":
    main()


# http://dev8.dev8.corp.lacework.net/api/v2/data/cmpl/evals/MDYxNzI0N2UtMTc3Mi00MGY1LWI0M2YtZTRhMDE4NWQzODA5LDUwMDAsNTIyNjIsMA
# lacework --nocache --debug api get /api/v2/data/cmpl/evals/MDYxNzI0N2UtMTc3Mi00MGY1LWI0M2YtZTRhMDE4NWQzODA5LDUwMDAsNTIyNjIsMA --profile=dev8
