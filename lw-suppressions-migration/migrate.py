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
AWSEXCEPTIONCSV="aws_exceptions.csv"

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

def parsePolicyLink (policylink):
    #format  [lacework-global-36](/catalog/policies/lacework-global-36)
    policyp=re.compile("\[([\w-]+)")
    try:
        policy=policyp.match(policylink)[0]
    except: 
        raise Exception ("Error parsing policy ID from markup link ", policylink)
    return policy

def import_aws_exceptions ():
    mappings={}
    with open(AWSEXCEPTIONCSV, newline='') as csvfile:
      mapreader = csv.reader(csvfile, delimiter='|')
      for row in mapreader:
        cisrule=row[1].strip(" ")
        policy=parsePolicyLink(row[2].strip(" ")) #format  [lacework-global-36](/catalog/policies/lacework-global-36)
        exception=row[3].strip(" ")
        manualp = re.compile("[Mm]anual") # TODO: simply remove the Manual policies from the CSV
        if not manualp.match(exception): 
            print(cisrule,'->',policy,":",exception)
            mappings[policy]=exception
    return mappings



def createPayload (awssupppresions, awsmap, awsexceptions):
    payloadsText=[]
    for k,v in awssuppressions.items():
        if k in awsmap and v["enabled"] and v["suppressionConditions"] is not None:
            payload = {}
            payload["description"]="Migration from old policy "+k
            payload["constraints"]=[]
            # print ("+++Policy ID ",k)
            for field,value in v["suppressionConditions"][0].items():
                #From https://docs.lacework.com/console/aws-compliance-policy-exceptions-criteria#cis-aws-140---exception-criteria
                #There are 2 kind of policies, those that ONLY take Account ID, those that also take Resource Names and Resource Tags
                if len(value)>0:
                    #print (".....",k, awsmap[k])
                    if (awsmap[k] in awsexceptions and awsexceptions[awsmap[k]] == "Account Ids"): #protect for the case where the Suppressions CSV doesn't haved a policy that shows up in Mappings
                        #this LPP policy only supports Account fieldkey
                        if field != "accountIds":
                            continue #skip any other fieldKey for policies that only accept Account ID
                    # print ("+++++",field, value)
                    constraint={}
                    constraint["fieldKey"]=field
                    if "ALL_" in str(value):
                        constraint["fieldValues"]=["*"]
                    else:
                        constraint["fieldValues"]=value
                    payload["constraints"].append(constraint)
            lwapitext = "lacework api post '/Exceptions?policyId=" + awsmap[k] + "' -d '" + json.dumps(payload) + "'"
            print (lwapitext)
            payloadsText.append(lwapitext)

    return payloadsText

awsmap = import_aws()
awsexceptions = import_aws_exceptions()
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
payloads=createPayload(awssuppressions, awsmap, awsexceptions)

#AWS_CIS_1_11   [{'accountIds': ['716829324861'], 'regionNames': ['ALL_REGIONS'], 'resourceNames': [], 'resourceTags': [], 'comments': ''}]
#▸ Valid constraint keys for aws polices are 'accountIds', 'resourceNames', 'regionNames' and 'resourceTags'`

