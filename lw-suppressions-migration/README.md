# Suppressions (v1) to Policy Exceptions (v2) Migration Helper for Lacework CSPM Policies

Python tool based on Lacework Python SDK that produces the necessary CLI calls as a script to create Policy Exceptions that map AWS CIS 1.4 policies with the old CIS 1.1 ones

The mappings between the old and the new CIS policies are documented [here](https://docs.lacework.com/console/cis-aws-140-benchmark-report#mapping-between-legacy-lacework-rules-and-latest-lacework-policies)

This tool is provided AS-IS and without any warranty nor expectations of support from Lacework. Use at your own risk

## Requirements
- Python 3.x
- [Lacework CLI](https://docs.lacework.com/cli/) Installed and configured to a valid Lacework Tenant with existing AWS Policy suppressions
- [Lacework Python SDK](https://github.com/lacework/python-sdk): `pip3 install laceworksdk`

### Working with multiple lacework CLI profiles
Before (and after) running this tool, ensure your active (default) Lacework profile is the one you want to use for this migration. The source and destination of the migration has to be the same account, do not use it by reading Suppressions from account A and then execute the script output on Account B

## Usage

`python3 migrate.py`

or

`python3 migrate.py > script.sh` 

if you want to review the output script as a text file instead of console output

For more verbose output, use
`python3 migrate.py -v` 



## Output Sample

This python tool outputs the a list of API calls with the raw API calls what will configure Policy Exceptions to the equivalent policies found in this [mapping](https://docs.lacework.com/console/cis-aws-140-benchmark-report#mapping-between-legacy-lacework-rules-and-latest-lacework-policies) but taking into consideration that the new policies do not accept exactly the same [Constraints](https://docs.lacework.com/console/aws-compliance-policy-exceptions-criteria#aws-cis-110---exception-criteria)

```
lacework api post '/Exceptions?policyId=lacework-global-141' -d '{"description": "Migrating suppression 0 from old policy LW_AWS_IAM_13", "constraints": [{"fieldKey": "accountIds", "fieldValues": ["*"]}, {"fieldKey": "resourceNames", "fieldValues": ["arn:aws:iam::1234567890:user/testuser"]}]}'

lacework api post '/Exceptions?policyId=lacework-global-68' -d '{"description": "Migrating suppression 0 from old policy AWS_CIS_4_1", "constraints": [{"fieldKey": "accountIds", "fieldValues": ["*"]}, {"fieldKey": "regionNames", "fieldValues": ["ap-southeast-1"]}, {"fieldKey": "resourceNames", "fieldValues": ["*"]}]}'

lacework api post '/Exceptions?policyId=lacework-global-68' -d '{"description": "Migrating suppression 1 from old policy AWS_CIS_4_1", "constraints": [{"fieldKey": "accountIds", "fieldValues": ["*"]}, {"fieldKey": "regionNames", "fieldValues": ["*"]}, {"fieldKey": "resourceTags", "fieldValues": [{"key": "suppress", "value": "true"}]}]}'

lacework api post '/Exceptions?policyId=lacework-global-41' -d '{"description": "Migrating suppression 0 from old policy AWS_CIS_1_11", "constraints": [{"fieldKey": "accountIds", "fieldValues": ["1234567890"]}, {"fieldKey": "regionNames", "fieldValues": ["*"]}]}'

### Discarded Constraints ###
#lacework-global-53 regionNames ['ALL_REGIONS']
```

The last section "Discarded Constraints" tells you which constraints were not possible to migrate based on our documented mappings in this Python tool, but you can go ahead and try to set them up in the UI, just in case we have a bug in this tool.

## What to do next

Users are strongly encoureged to review the Output script (list of Lacework CLI calls to execute) before executing those CLI calls.

> :warning: Running the script twice will create duplicate entries in the Policy Exceptions

## Possible BUGS

If you see something like this
```
ERROR unable to send the request: 
  [POST] https://lwintmarcgarcia.lacework.net/api/v2/Exceptions?policyId=lacework-global-41
  [400] fieldKey: regionNames is not applicable to policy lacework-global-41
```

it means unfortunately I didn't map the policies constraints properly. Edit the file "migrate.py" and locate the *equivalences_map* variable, find the LPP policy number, and edit accordingly, for instance

From 

`"AWS_CIS_1_3" : LPP("41",all_c),`

to

`"AWS_CIS_1_3" : LPP("41",res_c),`
