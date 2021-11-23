import argparse
import json
import subprocess


def make_request_and_parse_response(config_map, type):
    if config_map:
        config_map = json.dumps(config_map)
        response = subprocess.run([
            "lacework", "api", "patch", "/api/v1/external/recommendations/gcp",
            "-d", config_map
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
        ["lacework", "api", "get", "/api/v1/external/recommendations/gcp"],
        shell=False,
        capture_output=True)
    checkers = json.loads(response.stdout.decode("utf-8"))['data'][0]

    checkers_12 = [checker for checker in checkers if ("gcp_cis12" in checker.lower())]
    checkers_10 = [
        checker for checker in checkers if ("gcp_cis_" in checker.lower())
    ]
    checkers_lw_custom = [
        checker for checker in checkers if ("lw_gcp_" in checker.lower())
    ]
    checkers_k8s = [
        checker for checker in checkers if ("gcp_k8s_" in checker.lower())
    ]

    checkers_12.sort()
    checkers_10.sort()
    checkers_lw_custom.sort()
    checkers_k8s.sort()

    disable_map_10 = {}
    enable_map_10 = {}
    for checker in checkers_10:
        disable_map_10[checker] = 'disable'
        enable_map_10[checker] = 'enable'

    disable_map_12 = {}
    enable_map_12 = {}
    for checker in checkers_12:
        disable_map_12[checker] = 'disable'
        enable_map_12[checker] = 'enable'

    disable_map_lw_custom = {}
    enable_map_lw_custom = {}
    for checker in checkers_lw_custom:
        disable_map_lw_custom[checker] = 'disable'
        enable_map_lw_custom[checker] = 'enable'

    disable_map_k8s = {}
    enable_map_k8s = {}
    for checker in checkers_k8s:
        disable_map_k8s[checker] = 'disable'
        enable_map_k8s[checker] = 'enable'

    if flag == 'disable_cis_10':
        make_request_and_parse_response(disable_map_10, "CIS 1.0")

    elif flag == 'enable_cis_10':
        make_request_and_parse_response(enable_map_10, "CIS 1.0")

    elif flag == 'disable_cis_12':
        make_request_and_parse_response(disable_map_12, "CIS 1.2")

    elif flag == 'enable_cis_12':
        make_request_and_parse_response(enable_map_12, "CIS 1.2")

    elif flag == 'disable_lw_custom':
        make_request_and_parse_response(disable_map_lw_custom, "LW Custom")

    elif flag == 'enable_lw_custom':
        make_request_and_parse_response(enable_map_lw_custom, "LW Custom")

    elif flag == 'disable_k8s':
        make_request_and_parse_response(disable_map_k8s, "LW K8s")

    elif flag == 'enable_k8s':
        make_request_and_parse_response(enable_map_k8s, "LW K8s")

    elif flag == 'disable_all':
        make_request_and_parse_response(
            {
                **disable_map_12,
                **disable_map_10,
                **disable_map_lw_custom,
                **disable_map_k8s
            }, "ALL")

    elif flag == 'enable_all':
        make_request_and_parse_response(
            {
                **enable_map_12,
                **enable_map_10,
                **enable_map_lw_custom,
                **enable_map_k8s
            }, "ALL")


def parse_args():
    parser = argparse.ArgumentParser(description='Enable/Disable checkers')
    parser.add_argument(
        'flag',
        action='store',
        help='Flag to determine which checkers should be enabled/disabled. '
        'Accepts one of: [disable_cis_10|enable_cis_10|disable_cis_12|enable_cis_12|enable_all|disable_all|enable_k8s|disable_k8s|enable_lw_custom|disable_lw_custom]'
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
