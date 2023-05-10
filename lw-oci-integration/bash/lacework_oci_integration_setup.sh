#!/bin/bash

if ! which jq > /dev/null; then
    echo "this script requires jq - install jq to continue"
    exit 1
fi

if ! which oci > /dev/null; then
    echo "this script requires oci cli - install oci to continue"
    exit 1
fi

if ! which lacework > /dev/null; then
    echo "this script requires lacework cli - install lacework to continue"
    exit 1
fi

LOGFILE=/tmp/lacework_oci_integration.log
function log {
    echo `date -u +"%Y-%m-%dT%H:%M:%SZ"`" $1"
    echo `date -u +"%Y-%m-%dT%H:%M:%SZ"`" $1" >> $LOGFILE
}
truncate -s 0 $LOGFILE

function select_lacework_profile {
    log "select a lacework profile:"
    # Get the current tenant
    local options=$(lacework configure list | sed 's/>/ /' | awk -v m=2 -v n=3 'NR<=m{next};NR>n+m{print line[NR%n]};{line[NR%n]=$0}' | cut -d " " -f5)
    local IFS=$'\n'
    select opt in $options; do
        if [[ -n "$opt" ]]; then
            LACEWORK_PROFILE=$opt
            log "selected lacework profile: $LACEWORK_PROFILE"
            LACEWORK_ACCOUNT=$(lacework configure show account --profile=$LACEWORK_PROFILE)
            break
        fi
    done
}

log "Starting lacework integration..."
LACEWORK_PROFILE=""
LACEWORK_OIC_USERNAME="lacework_user_security_audit"
LACEWORK_OIC_GROUPNAME="lacework_group_security_audit"
LACEWORK_OCI_POLICYNAME="lacework_policy_security_audit"

log "Starting..."
select_lacework_profile
read -p "> Lacework OCI Username [default: $LACEWORK_OIC_USERNAME]: " lw_uname
if [ ! -z $lw_uname ]; then
    LACEWORK_OIC_USERNAME=$lw_uname
fi
read -p "> Lacework OCI Groupname [default: $LACEWORK_OIC_GROUPNAME]: " lw_gname
if [ ! -z $lw_uname ]; then
    LACEWORK_OIC_GROUPNAME=$lw_gname
fi
read -p "> Lacework OCI Policyname[(default: $LACEWORK_OCI_POLICYNAME]: " lw_pname
if [ ! -z $lw_uname ]; then
    LACEWORK_OCI_POLICYNAME=$lw_pname
fi

log "Lacework cli profile: $LACEWORK_PROFILE"
log "Lacework oci username: $LACEWORK_OIC_USERNAME"
log "Lacework oci groupname: $LACEWORK_OIC_GROUPNAME"
log "Lacework oci policyname: $LACEWORK_OCI_POLICYNAME"

log "Creating lacework oci user $LACEWORK_OIC_USERNAME"
LACEWORK_OCI_USER=$(oci iam user create --name $LACEWORK_OIC_USERNAME --description "A read only Lacework user to access resource configs." --email example@example.com | jq -r '.data.id')
log "Result: $LACEWORK_OCI_USER"
log "Creating lacework oci group $LACEWORK_OIC_GROUPNAME"
LACEWORK_OCI_GROUP=$(oci iam group create --name $LACEWORK_OIC_GROUPNAME --description "A lacework group needed to assign necessary read only permissions to lacework_user_security_audit." | jq -r '.data.id')
log "Result: $LACEWORK_OCI_GROUP"
log "Discovering tenant ocid..."
OCI_TENANCY_OCID=$(oci iam user get --user-id $LACEWORK_OCI_USER | jq -r '.data."compartment-id"')
log "Result: $OCI_TENANCY_OCID"
log "Discovering home region..."
OCI_HOME_REGION_SHORT=$(oci iam tenancy get --tenancy-id $OCI_TENANCY_OCID | jq -r '.data."home-region-key"')
log "Result: $OCI_HOME_REGION_SHORT"
log "Discovering home region long name..."
OCI_HOME_REGION=$(oci iam region list | jq -r ".data[] | select(.key==\"$OCI_HOME_REGION_SHORT\") | .name")
log "Result: $OCI_HOME_REGION"
log "Discovering tenant name..."
OCI_TENANT_NAME=$(oci iam tenancy get --tenancy-id $OCI_TENANCY_OCID | jq -r '.data.name')
log "Result: $OCI_TENANT_NAME"

log "Adding $LACEWORK_OIC_USERNAME user to $LACEWORK_OIC_GROUPNAME..."
oci iam group add-user --user-id $LACEWORK_OCI_USER --group-id $LACEWORK_OCI_GROUP
log "Assigning policy to grooup $LACEWORK_OIC_GROUPNAME..."
oci iam policy create \
   --compartment-id $OCI_TENANCY_OCID \
   --name $LACEWORK_OCI_POLICYNAME  \
   --description "Policy that grants necessary permissions to perform the security audit." \
   --statements "[\"Allow group '$LACEWORK_OIC_GROUPNAME' to inspect compartments in tenancy\", \
   \"Allow group '$LACEWORK_OIC_GROUPNAME' to read buckets in tenancy\", \
   \"Allow group '$LACEWORK_OIC_GROUPNAME' to read users in tenancy\", \
   \"Allow group '$LACEWORK_OIC_GROUPNAME' to inspect volumes in tenancy\", \
   \"Allow group '$LACEWORK_OIC_GROUPNAME' to inspect security-lists in tenancy\", \
   \"Allow group '$LACEWORK_OIC_GROUPNAME' to inspect subnets in tenancy\", \
   \"Allow group '$LACEWORK_OIC_GROUPNAME' to inspect network-security-groups in tenancy\", \
   \"Allow group '$LACEWORK_OIC_GROUPNAME' to inspect groups in tenancy\", \
   \"Allow group '$LACEWORK_OIC_GROUPNAME' to inspect instances in tenancy\", \
   \"Allow group '$LACEWORK_OIC_GROUPNAME' to inspect policies in tenancy\", \
   \"Allow group '$LACEWORK_OIC_GROUPNAME' to inspect domains in tenancy\", \
   \"Allow group '$LACEWORK_OIC_GROUPNAME' to inspect tag-defaults in tenancy\" ]"

LACEWORK_PRIVATE_KEY_PATH="$HOME/.oci/oci_api_key_lacework.pem"
LACEWORK_PUBLIC_KEY_PATH="$HOME/.oci/oci_api_key_lacework_public.pem"
LACEWORK_CLOUD_ACCOUNT_POLICY_PATH="$HOME/.oci/lacework_cloud_account_policy.json"

log "Creating key pair for $LACEWORK_OIC_USERNAME..."
mkdir ~/.oci
openssl genrsa -out $LACEWORK_PRIVATE_KEY_PATH 2048
chmod go-rwx $LACEWORK_PRIVATE_KEY_PATH
openssl rsa -pubout -in $LACEWORK_PRIVATE_KEY_PATH -out $LACEWORK_PUBLIC_KEY_PATH
log "Uploading public key for $LACEWORK_OIC_USERNAME..."
oci iam user api-key upload --user-id $LACEWORK_OCI_USER --key-file $LACEWORK_PUBLIC_KEY_PATH

log "Discovering key fingerprint..."
LACEWORK_PRIVATE_KEY_FINGERPRINT=$(openssl rsa -pubout -outform DER -in $LACEWORK_PRIVATE_KEY_PATH | openssl md5 -c > ~/.oci/lacework_fingerprint.txt && cat ~/.oci/lacework_fingerprint.txt)
log "Result: $LACEWORK_PRIVATE_KEY_FINGERPRINT"

log "Creating lacework cloud account policy..."
LACEWORK_INTEGRATION_NAME="oci-$OCI_TENANT_NAME"
contents=$(cat $LACEWORK_PRIVATE_KEY_PATH)
formatted_contents=$(echo "$contents" | awk '{ printf "%s\n", $0 }')
jq -n \
    --arg fc "$formatted_contents" \
    --arg li "$LACEWORK_INTEGRATION_NAME" \
    --arg ohc "$OCI_HOME_REGION" \
    --arg oti "$OCI_TENANCY_OCID" \
    --arg otn "$OCI_TENANT_NAME" \
    --arg oui "$LACEWORK_OCI_USER" \
    --arg fp "$LACEWORK_PRIVATE_KEY_FINGERPRINT" \
    '{"name": $li, "type": "OciCfg", "enabled": 1, "data": { "homeRegion": $ohc, "tenantId": $oti, "tenantName": $otn, "userOcid": $oui, "credentials": { "fingerprint": $fp, "privateKey": $fc }}}' > $LACEWORK_CLOUD_ACCOUNT_POLICY_PATH
log "Result: $(cat $LACEWORK_CLOUD_ACCOUNT_POLICY_PATH)"
log "Policy file: $LACEWORK_CLOUD_ACCOUNT_POLICY_PATH"

log "Waiting 60 seconds before posting policy to lacework..."
sleep 60

log "Posting policy via lacework api..."
lacework api post /api/v2/CloudAccounts -d "$(cat $LACEWORK_CLOUD_ACCOUNT_POLICY_PATH)" --profile=$LACEWORK_PROFILE
log "Listing integrated cloud accounts..."
lacework cloud-account list --profile=$LACEWORK_PROFILE