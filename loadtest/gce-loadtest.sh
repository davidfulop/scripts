#!/bin/bash
set -e
set -u

INSTANCE_NAME=load-testing-instance
GCP_PROJECT=$1
ARTILLERY_YML=$2
DATE=$(date +%s)
REMOTE_YML_PATH="/tmp/$ARTILLERY_YML"
RESULT_FILE=$ARTILLERY_YML"_results_"$DATE".json"
REPORT_FILE=$ARTILLERY_YML"_results_"$DATE".html"
REMOTE_RESULT_PATH="/tmp/"$RESULT_FILE
REMOTE_REPORT_PATH="/tmp/"$RESULT_FILE".html"

echo "Creating instance: $INSTANCE_NAME"
gcloud compute instances create $INSTANCE_NAME \
    --image-family ubuntu-1904 \
    --image-project ubuntu-os-cloud \
    --machine-type n1-highcpu-8

echo "Copying" $(pwd)"/"$ARTILLERY_YML "to" $REMOTE_YML_PATH
gcloud compute scp --zone europe-west1-b $(pwd)"/"$ARTILLERY_YML $INSTANCE_NAME:$REMOTE_YML_PATH

echo "Connecting to instance..."
gcloud compute ssh --project $GCP_PROJECT --zone europe-west1-b $INSTANCE_NAME -- \
    "echo 'Installing load testing tools...' \
    && sudo apt update && sudo apt upgrade -y \
    && sudo apt install -y nodejs npm \
    && npm install --ignore-scirpts artillery \
    && echo 'Starting load test...' \
    && node ~/node_modules/artillery/bin/artillery run $REMOTE_YML_PATH -o $REMOTE_RESULT_PATH \
    && echo 'Creating report...' \
    && node ~/node_modules/artillery/bin/artillery report $REMOTE_RESULT_PATH -o $REMOTE_REPORT_PATH"
echo "Copying result and report to local machine..."
gcloud compute scp --zone europe-west1-b $INSTANCE_NAME:$REMOTE_RESULT_PATH $(pwd)"/"$RESULT_FILE
gcloud compute scp --zone europe-west1-b $INSTANCE_NAME:$REMOTE_REPORT_PATH $(pwd)"/"$REPORT_FILE
