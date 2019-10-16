#!/bin/bash
set -e
set -u

INSTANCE_NAME=load-testing-instance
GCP_PROJECT=$1
ARTILLERY_YML=$2
REMOTE_YML_PATH="/tmp/$ARTILLERY_YML"
LOCAL_RESULT=$ARTILLERY_YML"_results_"$(date +%s)".json"
REMOTE_RESULT_PATH="/tmp/"$LOCAL_RESULT

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
    && sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y \
    && sudo apt install -y nodejs npm \
    && npm install --ignore-scirpts artillery \
    && echo 'Starting load test...' \
    && node ~/node_modules/artillery/bin/artillery run $REMOTE_YML_PATH -o $REMOTE_RESULT_PATH"

echo "Copying result file to local machine..."
gcloud compute scp --zone europe-west1-b $INSTANCE_NAME:$REMOTE_RESULT_PATH $(pwd)"/"$LOCAL_RESULT
echo "Creating report..."
artillery report $LOCAL_RESULT
