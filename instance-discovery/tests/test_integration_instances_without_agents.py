import sys
# setting path
sys.path.append('../instance-discovery')

import instances_without_agents

from argparse import Namespace
from unittest.mock import patch

# @patch('instances_without_agents.generate_subaccount_report')
# def test_integration_default_profile_json_output_mocked_data(mock_report):

#     # setup mocks
#     # TODO: Mock Agent data lookup
#     # TODO: Mock AWS data lookup
#     # TODO: Mock GCP data lookup
#     # TODO: Mock Azure data lookup
#     # TODO: Mock Fargate data lookup
#     # TODO: Do we need to mock the client object instantiation?
#     #mock_report.return_val = (1,[],[])

#     # setup input variables - Default profile - json output
#     # python3 instances_without_agents.py -p default --json
#     args = Namespace(account='', api_key='', api_secret='', subaccount='', profile='default', csv=False, json=True, debug=False, current_sub_account_only=True, statistics=False)
#     instances_without_agents.main(args)

#     # capture output
#     #out, err = capsys.readouterr()
#     out = ''
#     err = ''

#     # assertions
#     assert '"instances_with_agents"' in out 
#     assert '"instances_without_agents"' in out 
#     assert '"agents_without_inventory"' in out 
#     assert err == '' 