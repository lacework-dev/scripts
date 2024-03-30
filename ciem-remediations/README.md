# CIEM Remediations Tool (Policy Generator)

## Description

This is a tool which can use CIEM data from Lacework to generate a policy or set of policies reflecting only observed activity.  As an example, if an AWS IAM role has entitlements to access all APIs across the ec2, s3, and kms services, but Lacework has only observed the role access a handful of individual APIs, this script will generate a custom policy which only allows access to the observed APIs.

**WARNING:** before replacing any existing entitlements with the output from this tool, review them with the owners of the affected role.  Observed entitlements does not necessarily reflect all required entitlements (ie: some APIs may only be used occasionally and we may not have record of the last time they were used.)  Use this tool as a starting point!

AWS has a limitation on the number of non-whitespace characters in a policy (an inline role policy size can't exceed 10,240 characters and a managed policy can't exceed 6,144 characters).

The default behavior of this tool is to split generated policy documents up every ~6,000 characters. There are a few options on changing this behavior in the usage section below.

Supports CSV(s) downloaded from Lacework console, or provide arn(s) to pull directly from Lacework API.

## Usage

```
usage: generate-policy.py [-h] [--maxchars MAXCHARS] [--split {fewest-policies,by-service,none}] sources [sources ...]

Generate an IAM policy document containing observed IAM actions for a given IAM Role.

positional arguments:
  sources               Specify sources. Can be local CSV files exported from Lacework, or a list of ARNs to fetch from the Lacework API

optional arguments:
  -h, --help            show this help message and exit
  --maxchars MAXCHARS   Maximum size of a policy (does not count whitespace)
  --split {fewest-policies,by-service,none}
                        How to handle splitting large datasets. Default is 'fewest-policies'

Examples:
generate-policy.py arn:aws:iam:123456::role/some-role
generate-policy.py arn:aws:iam:123456::role/some-role arn:aws:123456::role/some-other-role
generate-policy.py /path/to/some.csv /path/to/some-other.csv
generate-policy.py arn:aws:iam:123456::role/some-role --split=by-service
```
