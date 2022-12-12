#!/bin/bash

# GKE Audit Log Integration - Manually using the GCP Console
# https://docs.lacework.com/onboarding/category/gke-audit-log-integrations-1

# Requirements
# - Decide if you want to monitor the GKE audit logs at the organization or project level. 
# -  If you specify the option to include children when creating the sink at the organization level, all the projects in the organization will export the audit logs to the bucket.
# - The procedure below requires that the jq utility is installed. The jq utility is a flexible command-line JSON processor. For more information, see https://stedolan.github.io/jq/

# Random String
RANDOM=$(xxd -l 4 -c 4 -p < /dev/random)

# GCP Variables
ORGANIZATION_ID="" # Populate this Variable if using Organization Level integration.
PROJECT_ID=""

# GCP Service Account - Populate these fields to use an existing service accounts, otherwise, one will be created.
SERVICE_ACCOUNT=""
CLIENT_ID=""
CLIENT_EMAIL=""
PRIVATE_KEY_ID=""
PRIVATE_KEY=""

# Lacework Variables - These can be found once Lacework API Key is created.
LACEWORK_ACCOUNT=""
LACEWORK_SUBACCOUNT=""
LACEWORK_API_KEY=""
LACEWORK_API_SECRET=""

# Constants
SERVICE_ACCOUNT_NAME="lwsvc-${RANDOM}"
SINK_NAME="lacework-gke-sink-${RANDOM}"
TOPIC_NAME="lacework-gke-topic-${RANDOM}"
TOPIC_SUB_NAME="lacework-gke-topic-sub-${RANDOM}"

# Set the current project by entering the following command.
gcloud config set project "$PROJECT_ID"

# Enable the required GCP APIs for integration.
gcloud services enable iam.googleapis.com pubsub.googleapis.com serviceusage.googleapis.com cloudresourcemanager.googleapis.com

# If a service account wasn't provided, then create one
if [ -z "$SERVICE_ACCOUNT" ]
then
    # Create the service account.
    SERVICE_ACCOUNT_JSON=$(gcloud iam service-accounts create $SERVICE_ACCOUNT_NAME --description="Lacework service account for GKE Audit Log monitoring" --display-name="lacework-gke-sa" --format json)
    SERVICE_ACCOUNT=$SERVICE_ACCOUNT_NAME
    CLIENT_ID=$(echo $SERVICE_ACCOUNT_JSON | jq -r '.uniqueId')
    CLIENT_EMAIL=$(echo $SERVICE_ACCOUNT_JSON | jq -r '.email')

    # Create a private key for the service account.
    TMP_KEY_FILE="./.lwsvc-tmp-key.json"
    gcloud iam service-accounts keys create $TMP_KEY_FILE --iam-account="$CLIENT_EMAIL" --format json
    PRIVATE_KEY_ID=$(cat $TMP_KEY_FILE | jq -r '.private_key_id')
    PRIVATE_KEY=$(cat $TMP_KEY_FILE | jq '.private_key')
    #rm $TMP_KEY_FILE
fi

# Grant the service account appropriate permissions.
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$CLIENT_EMAIL" --role="roles/monitoring.viewer"

# Create the pubsub topic.
gcloud pubsub topics create "$TOPIC_NAME"

# Create the sink.
# Decide if you want to export the audit logs at the organization or project level and create the sink. 
# If creating the sink at the organization level, add --include-children --organization=myorganizationid to the end of the following command.
# If you specify the --include-children option when creating the sink at the organization level, all the projects in the organization export audit logs to the bucket.
if [ -z "$ORGANIZATION_ID" ]
then
    SINK_SERVICE_ACCOUNT=$(gcloud logging sinks create $SINK_NAME "pubsub.googleapis.com/projects/$PROJECT_ID/topics/$TOPIC_NAME" \
        --log-filter "protoPayload.@type='type.googleapis.com/google.cloud.audit.AuditLog' AND protoPayload.serviceName = 'k8s.io'" \
        --exclusion=name=livezexclusion,description="Exclude livez logs",filter="protoPayload.resourceName=\"livez\" " \
        --exclusion=name=readyzexclusion,description="Exclude readyz logs",filter="protoPayload.resourceName=\"readyz\" " \
        --exclusion=name=metricsexclusion,description="Exclude metrics logs",filter="protoPayload.resourceName=\"metrics\" " \
        --exclusion=name=clustermetricsexclusion,description="Exclude cluster metrics logs",filter="protoPayload.resourceName=\"core/v1/namespaces/kube-system/configmaps/clustermetrics\" " \
        --format json | jq -r '.writerIdentity')
else
    SINK_SERVICE_ACCOUNT=$(gcloud logging sinks create $SINK_NAME "pubsub.googleapis.com/$TOPIC_NAME" \
        --oranization="$ORGANIZATION_ID" --include-children \
        --log-filter "protoPayload.@type='type.googleapis.com/google.cloud.audit.AuditLog' AND protoPayload.serviceName = 'k8s.io'" \
        --exclusion=name=livezexclusion,description="Exclude livez logs",filter="protoPayload.resourceName=\"livez\" " \
        --exclusion=name=readyzexclusion,description="Exclude readyz logs",filter="protoPayload.resourceName=\"readyz\" " \
        --exclusion=name=metricsexclusion,description="Exclude metrics logs",filter="protoPayload.resourceName=\"metrics\" " \
        --exclusion=name=clustermetricsexclusion,description="Exclude cluster metrics logs",filter="protoPayload.resourceName=\"core/v1/namespaces/kube-system/configmaps/clustermetrics\" " \
        --format json | jq -r '.writerIdentity')
fi

# If this is a new project, you must grant the GCP-managed service account sufficient privileges to publish to the log integration pubsub topic.
# Get the name of the GCP-managed service account that is created when a new project is created.
# This service account is in the format: service-YourProjectNumber@gs-project-accounts.iam.gserviceaccount.com. Replace YourProjectNumber with your value.
gcloud pubsub topics add-iam-policy-binding "projects/$PROJECT_ID/topics/$TOPIC_NAME" --member="$SINK_SERVICE_ACCOUNT" --role="roles/pubsub.publisher"

# Create the pubsub subscription (queue) for the GKE audit log data.
gcloud pubsub subscriptions create $TOPIC_SUB_NAME --topic "$TOPIC_NAME" --ack-deadline=300 --message-retention-duration=432000

# Grant the integration service account the subscriber role on the subscription. If prompted to install a command group, answer y.
gcloud pubsub subscriptions add-iam-policy-binding "projects/$PROJECT_ID/subscriptions/$TOPIC_SUB_NAME" --member="serviceAccount:$CLIENT_EMAIL" --role=roles/pubsub.subscriber

# BEGIN LACEWORK API CALLS

# Get Lacework Access Token via API
ACCESS_TOKEN=$(curl -s --location --request POST "https://$LACEWORK_ACCOUNT.lacework.net/api/v2/access/tokens" \
    --header "X-LW-UAKS: $LACEWORK_API_SECRET" \
    --header "Content-Type: application/json" \
    --data-raw "{
    \"keyId\": \"$LACEWORK_API_KEY\",
    \"expiryTime\": 3600
}" | jq -r '.token')

if [ -z "$ORGANIZATION_ID" ]
then
    # Perform GKE Audit Trail PROJECT Integration with Lacework
    curl --location --request POST "https://$LACEWORK_ACCOUNT.lacework.net/api/v2/CloudAccounts" \
        --header "Content-Type: application/json" \
        --header "Authorization: Bearer $ACCESS_TOKEN" \
        --header "Account-Name: $LACEWORK_SUBACCOUNT" \
        --data-raw "{
            \"name\": \"$PROJECT_ID-GKE-Audit\",
            \"type\": \"GcpGkeAudit\",
            \"enabled\": 1,
            \"data\": {
                \"credentials\": {
                    \"clientId\": \"$CLIENT_ID\",
                    \"clientEmail\": \"$CLIENT_EMAIL\",
                    \"privateKeyId\": \"$PRIVATE_KEY_ID\",
                    \"privateKey\": $PRIVATE_KEY
                },
                \"integrationType\": \"PROJECT\",
                \"projectId\": \"$PROJECT_ID\",
                \"subscriptionName\": \"projects/$PROJECT_ID/subscriptions/$TOPIC_SUB_NAME\"
            }
        }"
else
    # Perform GKE Audit Trail ORGANIZATION Integration with Lacework
    curl --location --request POST "https://$LACEWORK_ACCOUNT.lacework.net/api/v2/CloudAccounts" \
        --header "Content-Type: application/json" \
        --header "Authorization: Bearer $ACCESS_TOKEN" \
        --header "Account-Name: $LACEWORK_SUBACCOUNT" \
        --data-raw "{
            \"name\": \"$PROJECT_ID-GKE-Audit\",
            \"type\": \"GcpGkeAudit\",
            \"enabled\": 1,
            \"data\": {
                \"credentials\": {
                    \"clientId\": \"$CLIENT_ID\",
                    \"clientEmail\": \"$CLIENT_EMAIL\",
                    \"privateKeyId\": \"$PRIVATE_KEY_ID\",
                    \"privateKey\": $PRIVATE_KEY
                },
                \"integrationType\": \"ORGANIZATION\",
                \"projectId\": \"$PROJECT_ID\",
                \"subscriptionName\": \"projects/$PROJECT_ID/subscriptions/$TOPIC_SUB_NAME\",
                \"organizationId\": \"$ORGANIZATION_ID\"
            }
        }"
fi
