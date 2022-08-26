# Docs page: https://docs.lacework.com/console/aws-compliance-policy-exceptions-criteria
# CIS 1.1 to CIS 1.4 mappings https://docs.lacework.com/console/cis-aws-140-benchmark-report#whats-changed-from-cis-aws-11-to-cis-14

# TODO - deal with non-CIS policies

# TODO - process the known differences in Exception Configs between CIS 1.1 and CIS 1.4 rules from the Lacework Page
#  [400] fieldKey: regionNames is not applicable to policy lacework-global-53
#  [400] fieldKey: resourceNames is not applicable to policy lacework-global-76

import csv
import os
import re
import json
from laceworksdk import LaceworkClient

AWSCSV="aws_mappings.csv"
def import_aws ():
    mappings={}
    with open(AWSCSV, newline='') as csvfile:
      mapreader = csv.reader(csvfile, delimiter='|')
      for row in mapreader:
        old=row[1].strip(" ")
        new=row[3].strip(" ")
        if new.lower() == "n/a": continue
        manualp = re.compile("[Mm]anual") # TODO: simply remove the Manual policies from the CSV
        if manualp.match(new): continue
        # print(old+' -> '+new)
        mappings[old]=new
    return mappings

awsmap = import_aws()
try:
    lw = LaceworkClient() # This would leverage your default Lacework CLI profile. 
    data = lw.suppressions.get("aws")
    awssuppressions = data["data"][0]["recommendationExceptions"]
except:
    print ("Error fetching Exceptions from LW API")

# print  ("++ Showing only enabled policies with Suppressions ++")
# for k,v in awssuppressions.items():
#     if v["enabled"] and v["suppressionConditions"] is not None:
#         print (k, " ", v["suppressionConditions"])

print  ("++ Constructing the payload object ++")

for k,v in awssuppressions.items():
    if k in awsmap and v["enabled"] and v["suppressionConditions"] is not None:
        payload = {}
        payload["description"]="test payload"
        payload["constraints"]=[]
        # print ("+++Policy ID ",k)
        for field,value in v["suppressionConditions"][0].items():
            if len(value)>0:
                # print ("+++++",field, value)
                constraint={}
                constraint["fieldKey"]=field
                constraint["fieldValues"]=value
                payload["constraints"].append(constraint)

        print ("lacework api post '/Exceptions?policyId="+awsmap[k]+"' -d \\")
        print ("'",json.dumps(payload),"'")


#AWS_CIS_1_11   [{'accountIds': ['716829324861'], 'regionNames': ['ALL_REGIONS'], 'resourceNames': [], 'resourceTags': [], 'comments': ''}]
#▸ Valid constraint keys for aws polices are 'accountIds', 'resourceNames', 'regionNames' and 'resourceTags'`

