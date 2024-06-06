#!/bin/bash

RUBRIK_NODE_IP=10.38.196.28
base_url="https://${RUBRIK_NODE_IP}/api"
service_account_id="User:::2d2e37e2-f00f-4efc-9d2b-8e528e40795f"
secret="mu6vw0X5SntWKz/ocLg35ZvcNiIxb6x70iGP8C6G0qu9cath83uF01XKKr2LN1fw94h86rJEu8q8VF9vbwgt"
FS_ID="Fileset:::cd4f8854-fbae-4e76-b966-f63b20db6d43"
SLA_ID="b54672f0-6eb5-4d7c-9ebe-ff75c5dfb0ac"

# Get the session token
token=$(curl -s -k -X POST "${base_url}/v1/service_account/session" -H "accept: application/json" -H "Content-Type: application/json" -d "{\"serviceAccountId\": \"$service_account_id\", \"secret\": \"$secret\"}" | jq -r .token)

# Retrieve backup events
response=$(curl -s -k -X GET "${base_url}/v1/event/latest?limit=10&object_ids=$FS_ID&event_type=Backup" -H "accept: application/json" -H "Authorization: Bearer $token")

# Check if there are any running or scheduled backups
backupCount=$(echo "$response" | jq '.data | map(select(.latestEvent.eventType == "Backup" and (.latestEvent.eventStatus == "Running" or .eventSeriesStatus == "Scheduled" or .eventSeriesStatus == "Active"))) | length')

echo "Pending backup count is ${backupCount}"

if [ "$backupCount" -eq 1 ]; then
    echo "Since there is only one Backup running or scheduled, let's validate if it is in running or scheduled state."
    echo "$response" | jq -r '.data[] | select(.latestEvent.eventType == "Backup" and (.latestEvent.eventStatus == "Running" or .eventSeriesStatus == "Scheduled" or .eventSeriesStatus == "Active")) | "Job Instance ID: " + .latestEvent.jobInstanceId + ", Event Status: " + .latestEvent.eventStatus + ", Event Series Status: " + .eventSeriesStatus'
    EVENT_STATUS=$(echo "$response" | jq -r '.data[0].latestEvent.eventStatus')
    echo "$response" | jq -r '.data[0].latestEvent.eventStatus'
    echo $EVENT_STATUS
    if [ "$EVENT_STATUS" = "Running" ]; then
        echo "Backup is still running. Exiting..."
        curl -s -k -X DELETE "${base_url}/v1/session/me" -H "accept: application/json" -H "Authorization: Bearer $token"
        echo "Deleting Session and exiting"
        exit 0
    elif [ "$EVENT_STATUS" = "Queued" ] || [ "$EVENT_STATUS" = "Success" ] || [ "$EVENT_STATUS" = "TaskSuccess" ]; then
        echo "It is an SLA based Backup.Ignoring and proceeding with the on-demand backup or the previous backup just completed, proceeding with new one"
        echo "$response" | jq -r '.data[] | select(.latestEvent.eventType == "Backup" and (.latestEvent.eventStatus == "Running" or .eventSeriesStatus == "Scheduled" or .eventSeriesStatus == "Active")) | "Job Instance ID: " + .latestEvent.jobInstanceId + ", Event Status: " + .latestEvent.eventStatus + ", Event Series Status: " + .eventSeriesStatus'
    fi
fi

if [ "$backupCount" -gt 1 ]; then
    echo "Since backup count is greater than 1, it means at least one is an on-demand job waiting in the queue or Running Hence, exiting."
    echo "There is a running or scheduled on-demand backup. Exiting...SEE Below info"
    echo "$response" | jq -r '.data[] | select(.latestEvent.eventType == "Backup" and (.latestEvent.eventStatus == "Running" or .eventSeriesStatus == "Scheduled" or .eventSeriesStatus == "Active")) | "Job Instance ID: " + .latestEvent.jobInstanceId + ", Event Status: " + .latestEvent.eventStatus + ", Event Series Status: " + .eventSeriesStatus'
    echo "Deleting session and exiting"
    curl -s -k -X DELETE "${base_url}/v1/session/me" -H "accept: application/json" -H "Authorization: Bearer $token"

    exit 1
fi

# If no running or scheduled backups, proceed with initiating a new backup
response=$(curl -s -k -H "Authorization: Bearer $token" -X POST --header "Content-Type: application/json" -d '{"slaId":"'"$SLA_ID"'"}' "${base_url}/v1/fileset/${FS_ID}/snapshot")
JOB_ID=$(echo "$response" | jq -r '.id')
#echo "$JOB_ID"
echo "We have QUEUED $JOB_ID"
sleep 30

while true; do
    echo "$(date): Sleeping for 30 seconds..."
    sleep 30

    RESPONSE=$(curl -s -k -X GET "${base_url}/v1/event/latest?limit=1&object_ids=$FS_ID&event_type=Backup" -H "accept: application/json" -H "Authorization: Bearer $token")

    JOB_INSTANCE_ID=$(echo "$RESPONSE" | jq -r '.data[0].latestEvent.jobInstanceId')
    EVENT_STATUS=$(echo "$RESPONSE" | jq -r '.data[0].latestEvent.eventStatus')

    if [ "$JOB_INSTANCE_ID" = "$JOB_ID" ]; then
        echo "Job Instance ID matches: $JOB_INSTANCE_ID"
        echo "Event Status: $EVENT_STATUS"
        if [ "$EVENT_STATUS" = "Success" ]; then
            break
        fi
    elif [ "$EVENT_STATUS" = "Running" ]; then
        echo "Another backup is still running. Waiting for it to complete..."
    fi
done
curl -s -k -X DELETE "$base_url/v1/session/me" -H "accept: application/json" -H "Authorization: Bearer $token"
