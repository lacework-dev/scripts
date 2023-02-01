from laceworksdk import LaceworkClient
from laceworksdk.api.v1.suppressions import SuppressionsAPI
import argparse
import json

import logging

logger = logging.getLogger(__name__)

parser = argparse.ArgumentParser()
parser.add_argument("-p", "--profile", help="use a specific Lacework CLI profile")
parser.add_argument("-v", "--verbose", help="increase output verbosity",
                    action="store_true")
args = parser.parse_args()

if args.verbose:
    logging.basicConfig(level=logging.INFO)

# 'suppressionConditions': [{
#                     'accountIds': ['ALL_ACCOUNTS'],
#                     'regionNames': ['ALL_REGIONS'],
#                     'resourceNames': ['vpc-09c14e60'],
#                     'resourceTags': [],
#                     'comments': ''
#                 }]

class SuppressionsAPIOverride (SuppressionsAPI):
    def __init__(self, session):
        super().__init__(session)

    def get(self,
            type,
            recommendation_id=None):
        if recommendation_id:
            logger.info(f"Getting {type} suppression {recommendation_id} from Lacework...")
            api_uri = f"/api/v2/suppressions/{type}/allExceptions/{recommendation_id}"
        else:
            logger.info(f"Getting {type} suppressions from Lacework...")
            api_uri = f"/api/v2/suppressions/{type}/allExceptions"
        response = self._session.get(api_uri)
        logger.info(f"Got these suppressions from Lacework..."+str(response.json()))
        return response.json()

class LaceworkClientOverride (LaceworkClient):
    def __init__(self,cliprofile=None):
        super().__init__(profile=cliprofile)
        self.suppressions = SuppressionsAPIOverride(session=self._session)



class LPP:
    def __init__(self, lw_policy_number, list_of_constraint_types):
        self.lwPolicyID = "lacework-global-" + lw_policy_number
        self.listOfConstraintTypes = list_of_constraint_types


# constraint types
# ResourceNames, in the old CIS1.1, works for EC2 instance ID,
# VPC ID, Group ID, ARN, ELB ID, Lambda name, IAM policy, etc)
all_c = ["accountIds", "regionNames", "resourceNames", "resourceTags"]
noReg_c = ["accountIds", "resourceNames", "resourceTags"]
account_c = ["accountIds"]
res_c = ["accountIds", "resourceNames"]
noTag_c = ["accountIds", "regionNames", "resourceNames"]

# https://docs.lacework.com/console/aws-compliance-policy-exceptions-criteria#lacework-custom-policies-for-aws-iam
# https://docs.lacework.com/console/cis-aws-140-benchmark-report#identity-and-access-management
# old ID to new ID mapping, using the old Constraints with the hope they match the new Constraints
equivalences_map = {
    "LW_S3_1": LPP("130", all_c),
    "LW_S3_2": LPP("131", all_c),
    "LW_S3_3": LPP("132", all_c),
    "LW_S3_4": LPP("133", all_c),
    "LW_S3_5": LPP("134", all_c),
    "LW_S3_6": LPP("135", all_c),
    "LW_S3_7": LPP("136", all_c),
    "LW_S3_8": LPP("137", all_c),
    "LW_S3_9": LPP("138", all_c),
    "LW_S3_10": LPP("139", all_c),
    "LW_S3_11": LPP("140", all_c),
    "LW_S3_12": LPP("94", all_c),
    "LW_S3_13": LPP("95", all_c),
    "LW_S3_14": LPP("72", all_c),
    "LW_S3_15": LPP("96", all_c),
    "LW_S3_16": LPP("97", all_c),
    "LW_S3_18": LPP("98", all_c),
    "LW_S3_19": LPP("99", all_c),
    "LW_S3_20": LPP("100", all_c),
    "LW_S3_21": LPP("101", all_c),
    "AWS_CIS_1_1": LPP("36", account_c),
    "AWS_CIS_1_2": LPP("39", res_c),
    "AWS_CIS_1_3": LPP("41", all_c),
    "AWS_CIS_1_4": LPP("43", res_c),
    "AWS_CIS_1_9": LPP("37", account_c),
    "AWS_CIS_1_10": LPP("38", account_c),
    "AWS_CIS_1_11": LPP("41", account_c),  # lacework-global-41 is 45 days, instead of 90
    "AWS_CIS_1_12": LPP("34", account_c),
    "AWS_CIS_1_13": LPP("35", account_c),
    "AWS_CIS_1_14": LPP("69", account_c),
    "AWS_CIS_1_15": LPP("33", account_c),
    "AWS_CIS_1_16": LPP("44", res_c),  # no iam policies to users
    "AWS_CIS_1_19": LPP("31", account_c),  # manual?
    "AWS_CIS_1_20": LPP("32", account_c),  # manual?
    "AWS_CIS_1_21": LPP("70", noReg_c),  # manual?
    "AWS_CIS_1_22": LPP("46", account_c),
    "AWS_CIS_1_23": LPP("40", res_c),
    "AWS_CIS_1_24": LPP("45", res_c),
    "LW_AWS_IAM_1": LPP("115", res_c),
    "LW_AWS_IAM_2": LPP("116", res_c),
    "LW_AWS_IAM_3": LPP("117", res_c),
    "LW_AWS_IAM_4": LPP("118", res_c),
    "LW_AWS_IAM_5": LPP("119", res_c),
    "LW_AWS_IAM_6": LPP("120", res_c),
    "LW_AWS_IAM_7": LPP("121", res_c),
    "LW_AWS_IAM_11": LPP("181", account_c),  # non-root user
    "LW_AWS_IAM_12": LPP("142", res_c),
    "LW_AWS_IAM_13": LPP("141", res_c),
    "LW_AWS_IAM_14": LPP("105", res_c),
    "AWS_CIS_2_1": LPP("53", account_c),
    "AWS_CIS_2_2": LPP("75", noTag_c),
    "AWS_CIS_2_3": LPP("54", noReg_c),  # s3 bucket cloudtrail log
    "AWS_CIS_2_4": LPP("55", noTag_c),
    "AWS_CIS_2_5": LPP("76", noTag_c),
    "AWS_CIS_2_6": LPP("56", noReg_c),  # s3 bucket cloudtrail log
    "AWS_CIS_2_7": LPP("77", all_c),
    "AWS_CIS_2_8": LPP("78", all_c),
    "AWS_CIS_2_9": LPP("79", all_c),
    "AWS_CIS_3_1": LPP("57", account_c),
    "AWS_CIS_3_2": LPP("58", account_c),
    "AWS_CIS_3_3": LPP("59", account_c),
    "AWS_CIS_3_4": LPP("60", account_c),
    "AWS_CIS_3_5": LPP("61", account_c),
    "AWS_CIS_3_6": LPP("82", account_c),
    "AWS_CIS_3_7": LPP("83", account_c),
    "AWS_CIS_3_8": LPP("62", account_c),
    "AWS_CIS_3_9": LPP("84", account_c),
    "AWS_CIS_3_10": LPP("85", account_c),
    "AWS_CIS_3_11": LPP("86", account_c),
    "AWS_CIS_3_12": LPP("63", account_c),
    "AWS_CIS_3_13": LPP("64", account_c),
    "AWS_CIS_3_14": LPP("65", account_c),
    "AWS_CIS_4_1": LPP("68", all_c),
    "AWS_CIS_4_2": LPP("68", all_c),
    "AWS_CIS_4_3": LPP("79", all_c),
    "AWS_CIS_4_4": LPP("87", all_c),
    # "AWS_CIS_4_5" : LPP("88 (Manual)",
    "LW_AWS_NETWORKING_1": LPP("227", noReg_c),  # sec-group
    "LW_AWS_NETWORKING_2": LPP("145", noReg_c),  # network acl
    "LW_AWS_NETWORKING_3": LPP("146", noReg_c),  # network acl
    "LW_AWS_NETWORKING_4": LPP("147", res_c),
    "LW_AWS_NETWORKING_5": LPP("148", all_c),
    "LW_AWS_NETWORKING_6": LPP("149", all_c),
    "LW_AWS_NETWORKING_7": LPP("228", all_c),
    "LW_AWS_NETWORKING_8": LPP("229", all_c),
    "LW_AWS_NETWORKING_9": LPP("230", all_c),
    "LW_AWS_NETWORKING_10": LPP("231", all_c),
    "LW_AWS_NETWORKING_11": LPP("199", all_c),
    "LW_AWS_NETWORKING_12": LPP("150", all_c),
    "LW_AWS_NETWORKING_13": LPP("151", all_c),
    "LW_AWS_NETWORKING_14": LPP("152", all_c),
    "LW_AWS_NETWORKING_15": LPP("153", all_c),
    "LW_AWS_NETWORKING_16": LPP("225", all_c),
    "LW_AWS_NETWORKING_17": LPP("226", all_c),
    "LW_AWS_NETWORKING_18": LPP("154", all_c),
    "LW_AWS_NETWORKING_19": LPP("155", all_c),
    "LW_AWS_NETWORKING_20": LPP("156", all_c),
    "LW_AWS_NETWORKING_21": LPP("104", all_c),
    "LW_AWS_NETWORKING_22": LPP("106", all_c),
    "LW_AWS_NETWORKING_23": LPP("107", all_c),
    "LW_AWS_NETWORKING_24": LPP("108", all_c),
    "LW_AWS_NETWORKING_25": LPP("109", all_c),
    "LW_AWS_NETWORKING_26": LPP("110", all_c),
    "LW_AWS_NETWORKING_27": LPP("111", all_c),
    "LW_AWS_NETWORKING_28": LPP("112", all_c),
    "LW_AWS_NETWORKING_29": LPP("113", all_c),
    "LW_AWS_NETWORKING_30": LPP("114", all_c),
    "LW_AWS_NETWORKING_31": LPP("218", all_c),
    "LW_AWS_NETWORKING_32": LPP("219", all_c),
    "LW_AWS_NETWORKING_33": LPP("220", all_c),
    "LW_AWS_NETWORKING_34": LPP("221", all_c),
    "LW_AWS_NETWORKING_35": LPP("222", all_c),
    "LW_AWS_NETWORKING_36": LPP("148", all_c),
    "LW_AWS_NETWORKING_37": LPP("102", all_c),
    "LW_AWS_NETWORKING_38": LPP("223", all_c),
    "LW_AWS_NETWORKING_39": LPP("184", all_c),
    "LW_AWS_NETWORKING_40": LPP("103", all_c),
    "LW_AWS_NETWORKING_41": LPP("125", noReg_c),  # cloudfront
    "LW_AWS_NETWORKING_42": LPP("126", noReg_c),  # cloudfront
    "LW_AWS_NETWORKING_43": LPP("127", all_c),
    "LW_AWS_NETWORKING_44": LPP("231", all_c),
    "LW_AWS_NETWORKING_45": LPP("482", all_c),
    "LW_AWS_NETWORKING_46": LPP("157", all_c),
    "LW_AWS_NETWORKING_47": LPP("128", all_c),
    "LW_AWS_NETWORKING_49": LPP("159", all_c),
    "LW_AWS_NETWORKING_50": LPP("129", noReg_c),  # cloudfront
    "LW_AWS_NETWORKING_51": LPP("483", all_c),
    "LW_AWS_MONGODB_1": LPP("196", all_c),  # not documented
    "LW_AWS_MONGODB_2": LPP("196", all_c),
    "LW_AWS_MONGODB_3": LPP("197", all_c),
    "LW_AWS_MONGODB_4": LPP("197", all_c),
    "LW_AWS_MONGODB_5": LPP("198", all_c),
    "LW_AWS_MONGODB_6": LPP("198", all_c),
    "LW_AWS_GENERAL_SECURITY_1": LPP("89", noReg_c),  # ec2 tags
    "LW_AWS_GENERAL_SECURITY_2": LPP("90", all_c),
    "LW_AWS_GENERAL_SECURITY_3": LPP("160", noReg_c),
    "LW_AWS_GENERAL_SECURITY_4": LPP("171", noReg_c),
    "LW_AWS_GENERAL_SECURITY_5": LPP("91", noReg_c),
    "LW_AWS_GENERAL_SECURITY_6": LPP("92", noTag_c),
    "LW_AWS_GENERAL_SECURITY_7": LPP("182", noReg_c),
    "LW_AWS_GENERAL_SECURITY_8": LPP("183", noReg_c),
    "LW_AWS_SERVERLESS_1": LPP("179", all_c),
    "LW_AWS_SERVERLESS_2": LPP("180", all_c),
    "LW_AWS_SERVERLESS_4": LPP("143", all_c),
    "LW_AWS_SERVERLESS_5": LPP("144", all_c),
    "LW_AWS_RDS_1": LPP("93", all_c),
    "LW_AWS_ELASTICSEARCH_1": LPP("122", noTag_c),
    "LW_AWS_ELASTICSEARCH_2": LPP("123", noTag_c),
    "LW_AWS_ELASTICSEARCH_3": LPP("124", noTag_c),
    "LW_AWS_ELASTICSEARCH_4": LPP("161", noTag_c)
}


def create_payload(aws_suppressions):
    payloads_text = []
    discarded_suppressions = []
    disabled_policies = []
    for k, v in aws_suppressions.items():
        # k is 'AWS_CIS_1_11'
        # v is {'enabled': False, 'suppressionConditions': [{'accountIds': ['716829324861'], 'regionNames': ['ALL_REGIONS'], 'resourceNames': [], 'resourceTags': [], 'comments': ''}]},
        # ignore enable/disabled, we want to migrate the suppressions, not the enablement of the policy
        if v["suppressionConditions"] is None:
            continue
        logging.info("Found Policy " + k + " with the following settings " + str(v))
        # assume we mapped 100% of the old AWS policies in equivalences_map
        if k not in equivalences_map.keys():
            logging.warning("Policy " + k + " is not mapped in this script")
            continue
        lpp_policy = equivalences_map[k].lwPolicyID
        supp_count = 0
        if not v["enabled"] and lpp_policy not in disabled_policies:
            logging.info("# Disabling policy " + lpp_policy + "as legacy policy was disabled")
            lw_api_text = "lacework policy disable " + lpp_policy
            print(lw_api_text + "\n")
            payloads_text.append(lw_api_text)

        # handle multiple suppressions per policy
        for suppressionCondition in v["suppressionConditions"]:
            payload = {
                "description": "Migrating suppression " +
                               str(supp_count) + " from old policy " + k, "constraints": []}
            for fieldKey, value in suppressionCondition.items():
                # check if LPP supports the same fieldKey as the old Suppression
                if fieldKey == "comments":
                    if value != "":
                        logging.info(
                            "# Original comment for suppression in policy " + k + ": " + value)
                    if value != "" and value is not None:
                        logging.info("# Original comment for suppression in policy " + k + ": " + value)
                elif fieldKey not in equivalences_map[k].listOfConstraintTypes:
                    if len(value) > 0:
                        logging.info(
                            "# LPP Policy " + lpp_policy +
                            " does not support the suppression condition " + fieldKey +
                            ". Discarding...")
                        discarded_suppressions.append((lpp_policy, fieldKey, value))
                elif len(value) > 0:  # only process constraints that have a value
                    constraint = {"fieldKey": fieldKey}
                    if "ALL_" in str(value):
                        constraint["fieldValues"] = ["*"]
                    else:
                        constraint["fieldValues"] = value
                    payload["constraints"].append(constraint)
            logging.info("# Creating Exception migration num " + str(
                supp_count) + "for a suppression that had constraint types: " + str(
                equivalences_map[k].listOfConstraintTypes))
            lw_api_text = "lacework api post '/Exceptions?policyId=" + lpp_policy + "' -d '" + \
                          json.dumps(payload) + "'"
            print(lw_api_text + "\n")
            payloads_text.append(lw_api_text)
            supp_count += 1

    print("### Discarded Constraints ###")
    for policy, k, v in discarded_suppressions:
        print("#" + policy, k, str(v))

    return payloads_text


def main():
    try:
        lw = LaceworkClientOverride(args.profile)
        data = lw.suppressions.get("aws")
        aws_suppressions = data["data"][0]["recommendationExceptions"]
        print("#### Constructing the script object")
        create_payload(aws_suppressions)
        print("#### End of script")
    except:
        logging.exception("Error fetching Exceptions from LW API")


if __name__ == "__main__":
    main()
