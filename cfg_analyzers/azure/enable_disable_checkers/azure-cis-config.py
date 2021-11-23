import argparse
import json
import subprocess


def make_request_and_parse_response(config_map, type):
    if config_map:
        config_map = json.dumps(config_map)
        response = subprocess.run([
            "lacework", "api", "patch",
            "/api/v1/external/recommendations/azure", "-d", config_map
        ],
                                  shell=False,
                                  capture_output=True)
        if response.returncode > 0:
            print("ERROR Response {}".format(response.stderr.decode('utf-8')))
            exit(response.returncode)
        else:
            print(response.stdout.decode('utf-8'))
    else:
        print("Nothing to do. No '{}' checkers found to enable/disable".format(
            type))


def generate_checker_map(flag):
    response = subprocess.run(
        ["lacework", "api", "get", "/api/v1/external/recommendations/azure"],
        shell=False,
        capture_output=True)
    checkers = json.loads(response.stdout.decode("utf-8"))['data'][0]

    checkers_131 = [
        checker for checker in checkers if ("azure_cis_131" in checker.lower())
    ]
    checkers_10 = [
        checker for checker in checkers
        if ("azure_cis_131" not in checker.lower()
            and "azure_cis_" in checker.lower())
    ]
    checkers_lw_custom = [
        checker for checker in checkers if ("lw_azure_" in checker.lower())
    ]

    checkers_131.sort()
    checkers_10.sort()
    checkers_lw_custom.sort()

    disable_map_10 = {}
    enable_map_10 = {}
    for checker in checkers_10:
        disable_map_10[checker] = 'disable'
        enable_map_10[checker] = 'enable'

    disable_map_131 = {}
    enable_map_131 = {}
    for checker in checkers_131:
        disable_map_131[checker] = 'disable'
        enable_map_131[checker] = 'enable'

    disable_map_lw_custom = {}
    enable_map_lw_custom = {}
    for checker in checkers_lw_custom:
        disable_map_lw_custom[checker] = 'disable'
        enable_map_lw_custom[checker] = 'enable'

    if flag == 'disable_cis_10':
        make_request_and_parse_response(disable_map_10, "CIS 1.0")

    elif flag == 'enable_cis_10':
        make_request_and_parse_response(enable_map_10, "CIS 1.0")

    elif flag == 'disable_cis_131':
        make_request_and_parse_response(disable_map_131, "CIS 1.3.1")

    elif flag == 'enable_cis_131':
        make_request_and_parse_response(enable_map_131, "CIS 1.3.1")

    elif flag == 'disable_lw_custom':
        make_request_and_parse_response(disable_map_lw_custom, "LW Custom")

    elif flag == 'enable_lw_custom':
        make_request_and_parse_response(enable_map_lw_custom, "LW Custom")

    elif flag == 'disable_all':
        make_request_and_parse_response(
            {
                **disable_map_131,
                **disable_map_10,
                **disable_map_lw_custom
            }, "ALL")

    elif flag == 'enable_all':
        make_request_and_parse_response(
            {
                **enable_map_131,
                **enable_map_10,
                **enable_map_lw_custom
            }, "ALL")


def parse_args():
    parser = argparse.ArgumentParser(description='Enable/Disable checkers')
    parser.add_argument(
        'flag',
        action='store',
        help='Flag to determine which checkers should be enabled/disabled. '
        'Accepts one of: [disable_cis_10|enable_cis_10|disable_cis_131|enable_cis_131|enable_all|disable_all|enable_lw_custom|disable_lw_custom]'
    )
    parser.add_argument(
        'lacework_tenant',
        action='store',
        help=
        'The lacework tenant you wish to target. MUST match the configure tenant on your Lacework CLI.'
    )
    args = parser.parse_args()
    flag = args.flag
    lacework_tenant = args.lacework_tenant

    response = subprocess.run(["lacework", "configure", "list"],
                              shell=False,
                              capture_output=True)

    if response.returncode > 0:
        print("ERROR: {}".format(response.stderr.decode('utf-8')))
        exit(response.returncode)

    lacework_cli_configured_tenant = response.stdout.decode(
        "utf-8").strip().split('>')[1].split()[1]

    if lacework_tenant != lacework_cli_configured_tenant:
        print("Error: Provided lacework tenant: " + lacework_tenant +
              " does not match the configured tenant on the Lacework CLI: " +
              lacework_cli_configured_tenant)
        exit(1)

    generate_checker_map(flag)


if __name__ == '__main__':
    parse_args()
