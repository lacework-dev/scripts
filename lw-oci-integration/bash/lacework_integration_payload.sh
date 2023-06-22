#!/bin/bash

if ! which jq > /dev/null; then
    echo "this script requires jq - install jq to continue"
    exit 1
fi

OUTPUT_FILE="lacework_payload.json"

# Values of 6 variables below should be changed before running script:

LACEWORK_OCI_USERNAME="<user_ocid>"
OCI_TENANCY_OCID="<tenancy_ocid>"
OCI_HOME_REGION="<home_region>"
OCI_TENANT_NAME="<tenant_name>"
LACEWORK_PRIVATE_KEY_PATH="<private_key_path>"
LACEWORK_PRIVATE_KEY_FINGERPRINT="<fingerprint>"

LACEWORK_INTEGRATION_NAME="oci-$OCI_TENANT_NAME"
contents=$(cat $LACEWORK_PRIVATE_KEY_PATH)
formatted_contents=$(echo "$contents" | awk '{ printf "%s\n", $0 }')
jq -n \
    --arg fc "$formatted_contents" \
    --arg li "$LACEWORK_INTEGRATION_NAME" \
    --arg ohc "$OCI_HOME_REGION" \
    --arg oti "$OCI_TENANCY_OCID" \
    --arg otn "$OCI_TENANT_NAME" \
    --arg oui "$LACEWORK_OCI_USERNAME" \
    --arg fp "$LACEWORK_PRIVATE_KEY_FINGERPRINT" \
    '{"name": $li, "type": "OciCfg", "enabled": 1, "data": { "homeRegion": $ohc, "tenantId": $oti, "tenantName": $otn, "userOcid": $oui, "credentials": { "fingerprint": $fp, "privateKey": $fc }}}' > $OUTPUT_FILE
