#!/bin/bash
set -e
set -u

INSTANCE_NAME=load-testing-instance
GCP_PROJECT=$1
ARTILLERY_YML=$2
DATE=$(date +%s)
LOCAL_RESULT_DIR="./results"
REMOTE_YML_PATH="/tmp/$ARTILLERY_YML"
RESULT_FILE_NAME=$ARTILLERY_YML"_results_"$DATE
RESULT_PATH=$LOCAL_RESULT_DIR"/"$RESULT_FILE_NAME".json"
REPORT_PATH=$LOCAL_RESULT_DIR"/"$RESULT_FILE_NAME".html"
REMOTE_RESULT_PATH="/tmp/"$RESULT_FILE_NAME".json"
REMOTE_REPORT_PATH="/tmp/"$RESULT_FILE_NAME".html"

echo "Creating instance: $INSTANCE_NAME"
gcloud compute instances create $INSTANCE_NAME \
    --image-family ubuntu-1904 \
    --image-project ubuntu-os-cloud \
    --machine-type n1-highcpu-8 \
    --preemptible

echo "Copying" $ARTILLERY_YML "to" $REMOTE_YML_PATH
gcloud compute scp --zone europe-west1-b $ARTILLERY_YML $INSTANCE_NAME:$REMOTE_YML_PATH

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
if [ ! -d $LOCAL_RESULT_DIR ]; then
  mkdir $LOCAL_RESULT_DIR
fi

gcloud compute scp --zone europe-west1-b $INSTANCE_NAME:$REMOTE_RESULT_PATH $RESULT_PATH
gcloud compute scp --zone europe-west1-b $INSTANCE_NAME:$REMOTE_REPORT_PATH $REPORT_PATH

echo "Deleting instance: $INSTANCE_NAME"
gcloud compute instances delete --quiet --zone europe-west1-b $INSTANCE_NAME
echo "Instance deleted, have a good day!"
