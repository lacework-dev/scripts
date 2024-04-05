# CIEM Remediations Tool (Policy Generator)

## Description

⚠️ **This tool supports AWS identities only** ⚠️

This is a tool which can use CIEM data from Lacework to generate a policy or set of policies reflecting only observed activity.  As an example, if an AWS IAM role has entitlements to access all APIs across the ec2, s3, and kms services, but Lacework has only observed the role access a handful of individual APIs, this script will generate a custom policy which only allows access to the observed APIs.

**WARNING:** before replacing any existing entitlements with the output from this tool, review them with the owners of the affected role.  Observed entitlements does not necessarily reflect all required entitlements (ie: some APIs may only be used occasionally and we may not have record of the last time they were used.)  Use this tool as a starting point!d

**Supported Sources**
- CSV(s) downloaded from Lacework console
- ARN(s) to pull directly from Lacework API.


## How it works

![how-it-works](./images/how-it-works.png)

Lacework entitlement data for AWS is comprised of a list of identities, their granted entitlements, and historic usage data (observed via CloudTrail). Users can use the Lacework dashboard to view a list of *used* and *unused* entitlements for a given identity.  To right-size an identity, you may replace existing entitlements with a custom policy containing only the *used* entitlements observed by Lacework.

To create a custom policy for a given identity (or a single policy for a set of identities, see below), you can either run this tool against exported CSV files from the Lacework console, or provide the ARN(s) of target identity(s) directly on the command line (requires Lacework API credentials)

### Using with CSV files

Export CSV files from Lacework console to a local path

```bash
generate-policy.py /path/to/export.csv [/path/to/other-export.csv]
```

### Using with ARNs (requires Lacework API credentials)

If you have a `~/.lacework.toml` configured with a default profile, it will use this by default:

```bash
generate-policy.py arn:aws:iam:123456::role/some-role [arn:aws:iam:123456::role/some-other-role]
```

If you want to use a different configured profile, specify it as shown:

```bash
export LW_PROFILE=some-profile
generate-policy.py arn:aws:iam:123456::role/some-role [arn:aws:iam:123456::role/some-other-role]
```

You may also specify API credentials directly
```bash
export LW_ACCOUNT="<YOUR_ACCOUNT>"
export LW_API_KEY="<YOUR_API_KEY>"
export LW_API_SECRET="<YOUR_API_SECRET>"
export LW_SUBACCOUNT="business-unit" # (optional)
generate-policy.py arn:aws:iam:123456::role/some-role [arn:aws:iam:123456::role/some-other-role]
```

## Output

The output of this tool is a JSON list of policies.  By default it will echo to `STDOUT` but can be directed to a file or piped to another process as shown:

```bash
generate-policy.py source [source] > output.csv
generate-policy.py source [source] | /some/other/tool
```

## AWS Maximum Policy Size Limitations

AWS has a limitation on the number of non-whitespace characters in a policy.  This tool will automatically split large policies into multiple smaller policies which can be overridden with the `--maxchars` argument.

| Policy Type | Maximum Size |
|---|---|
| Inline Role Policy | 10,240 characters |
| Managed Policy | 6,144 characters (default) |

To change the maximum size of a policy, use the `--maxchars` argument.

Example:

```bash
generate-policy.py --maxchars 10240 source [source]
```

## Policy splitting behaviors

You may control the behavior for policy splitting using the `--split` argument:

| Option | Description |
|---|---|
| `fewest-policies` (default) | Tries to generate similarly sized policies by separating into groups of services. In some scenarios a policy may contain actions from multiple services, but these will be grouped together. <br><br>Actions from a single service will never span multiple policies, unless it is too big as a standalone policy, in which case it will be separated into multiple standalone polices for that service alone. In other words, you will not see actions from multiple services spread across multiple policies containing other actions from other services. |
| `by-service` | Will create separate policies for each service. If a given service has too many actions for a single policy (defined by `maxchars`) then it will be separated into multiple policies |
| `none` | Do not split the output at all, will return a single policy regardless of `maxchars` |

---

`fewest-policies` Example:

```bash
generate-policy.py --split=fewest-policies source [source]
```
<details>
  <summary>Show Output</summary>
  
  ```json
  [
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Sid": "Stmt611596984",
          "Action": [
            "cloudtrail:DescribeTrails",
            "cloudtrail:GetEventSelectors",
            "firehose:ListDeliveryStreams",
            "glue:GetDatabases",
            "states:DescribeStateMachine",
            "states:ListStateMachines",
            "waf:ListWebACLs",
            "waf-regional:ListWebACLs",
            "wafv2:ListIPSets",
            "wafv2:ListRegexPatternSets",
            ...(actions populate in groups of services until maxchars is hit, then another policy begins)
          ],
          "Effect": "Allow",
          "Resource": "*"
        }
      ]
    },
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Sid": "Stmt219043297",
          "Action": [
            ...(continued list of actions grouped by service)
            "appsync:ListDomainNames",
            "appsync:ListGraphqlApis",
            "config:DescribeConfigurationRecorderStatus",
            "config:DescribeConfigurationRecorders",
            "kinesis:ListStreams",
            "kms:Decrypt",
            "kms:DescribeKey",
            ...
          ],
          "Effect": "Allow",
          "Resource": "*"
        },
      ]
    },
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Sid": "Stmt391922664",
          "Action": [
            "sagemaker:ListActions",
            "sagemaker:ListAlgorithms",
            ... (large lists of actions for a single service may be split into multiple dedicated policies)
          ],
          "Effect": "Allow",
          "Resource": "*"
        }
      ]
    },
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Sid": "Stmt391922664",
          "Action": [
            ... (this is a continuation of previous policy)
            "sagemaker:ListLabelingJobs",
            "sagemaker:ListLineageGroups",
            ...
          ],
          "Effect": "Allow",
          "Resource": "*"
        }
      ]
    },
    ...(additional policies containing groups of services continue here)
  ]
  ```
</details>

---

`by-service` Example:

```bash
generate-policy.py --split=by-service source [source]
```
<details>
  <summary>Show Output</summary>
  
  ```json
  [
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Sid": "Stmt354773700",
          "Action": [
            "dms:DescribeAccountAttributes",
            "dms:DescribeCertificates",
            ...
          ],
          "Effect": "Allow",
          "Resource": "*""
        }
      ]
    },
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Sid": "Stmt354773700",
          "Action": [
            "elasticfilesystem:DescribeAccessPoints",
            "elasticfilesystem:DescribeAccountPreferences",
            ...
          ],
          "Effect": "Allow",
          "Resource": "*"
        }
      ]
    },
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Sid": "Stmt391922664",
          "Action": [
            "sagemaker:ListActions",
            "sagemaker:ListAlgorithms",
            ... (large lists of actions may be split into multiple policies)
          ],
          "Effect": "Allow",
          "Resource": "*"
        }
      ]
    },
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Sid": "Stmt391922664",
          "Action": [
            ... (this is a continuation of previous policy)
            "sagemaker:ListLabelingJobs",
            "sagemaker:ListLineageGroups",
            ...
          ],
          "Effect": "Allow",
          "Resource": "*"
        }
      ]
    },
    ... (additional services continue here)
  ]
  ```
</details>

---

`none` Example:

```bash
generate-policy.py --split=none source [source]
```
<details>
  <summary>Show Output</summary>
  
  ```json
  [
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Sid": "Stmt471312065",
          "Action": [
            "athena:GetWorkGroup",
            "athena:ListApplicationDPUSizes",
            ...
            "dms:DescribeAccountAttributes",
            "dms:DescribeCertificates",
            ...
            "ec2:DescribeSnapshotAttribute",
            "ec2:DescribeSnapshots",
            ... (many more actions here, regardless of maxchars)
          ]
        }
      ]
    }
  ]
  ```
</details>


## Combined Policies

This tool supports combining used entitlements from multiple sources, into a single policy / set of policies.  A use case for this may be a set of roles used for multiple web services for a single application. A goal may be to consolidate all required entitlements across all services, into a single role for easier management.

You may add many sources (CSV and API sources can be mixed) to get a single consolidated policy.

Examples:

```bash
generate-policy.py arn:aws:iam:123456::role/some-role arn:aws:iam:123456::role/some-other-role
generate-policy.py /path/to/some.csv /path/to/some-other.csv
generate-policy.py /path/to/some.csv arn:aws:iam:123456::role/some-role [and so on...]
```


## Usage

```
usage: generate-policy.py [-h] [--maxchars MAXCHARS] [--split {fewest-policies,by-service,none}] source [source ...]

Generate an IAM policy document containing observed IAM actions for a given IAM Role.

positional arguments:
  source               Specify source(s). Can be local CSV files exported from Lacework, or a list of ARNs to fetch from the Lacework API

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
