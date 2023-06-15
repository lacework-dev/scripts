#!/bin/bash

if ! which jq > /dev/null; then
    echo "this script requires jq - install jq to continue"
    exit 1
fi

OUTPUT_FILE="lacework_payload.json"

LACEWORK_OCI_USERNAME="ocid1.user.oc1..aaaaaaaaa3sq6j7icod2o6iky5smahcgt6xurxkuxzigyumpcg4rgyq5abcd"
OCI_TENANCY_OCID="ocid1.tenancy.oc1..aaaaaaaatxph3zpu3jkem4cseejktwllb6dgsam7cx3jy63pazejzobvabcd"
OCI_HOME_REGION="us-sanjose-1"
OCI_TENANT_NAME="main tenant"

LACEWORK_PRIVATE_KEY_PATH="/pathto/oci_api_key_lacework.pem"
LACEWORK_PRIVATE_KEY_FINGERPRINT="1c:17:64:82:0d:86:c8:1d:8a:b6:d1:12:b7:a4:b2:cc"

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
