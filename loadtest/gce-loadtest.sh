#!/bin/bash
set -e
set -u

PARAMS=""
MACHINE_TYPE="n1-highcpu-8"
GCP_PROJECT=$(gcloud config get-value project)

while :; do
    case $1 in
        -m|--machine-type)
            MACHINE_TYPE=$2
            shift 2
            ;;
        -p|--project)
            GCP_PROJECT=$2
            shift 2
            ;;
        --)
            shift
            ;;
        -?*)
            printf 'ERROR: encountered unknown option: %s, exiting\n' "$1" >&2
            exit 1
            ;;
        *)
            PARAMS="$PARAMS $1"
            break
            ;;
    esac
done

eval set -- "$PARAMS"

INSTANCE_NAME=load-testing-instance
GCP_ZONE=$(gcloud config get-value compute/zone)
ARTILLERY_YML=$1
DATE=$(date +%s)
LOCAL_RESULT_DIR="./results"
REMOTE_YML_PATH="/tmp/$ARTILLERY_YML"
RESULT_FILE_NAME=$ARTILLERY_YML"_results_"$DATE
RESULT_PATH=$LOCAL_RESULT_DIR"/"$RESULT_FILE_NAME".json"
REPORT_PATH=$LOCAL_RESULT_DIR"/"$RESULT_FILE_NAME".html"
REMOTE_RESULT_PATH="/tmp/"$RESULT_FILE_NAME".json"
REMOTE_REPORT_PATH="/tmp/"$RESULT_FILE_NAME".html"

echo "Using project: $GCP_PROJECT"

X=$(gcloud compute instances list load-testing-instance  --project $GCP_PROJECT | { grep -c $INSTANCE_NAME || true; })
if [ $X == 1 ]; then
    RUNNING=$(gcloud compute instances describe --project $GCP_PROJECT $INSTANCE_NAME | { grep -c "status: RUNNING" || true; })
    if [ $RUNNING == 0 ]; then
        echo "Instance already created, but not running; script terminating."
        exit 1
    else
        echo "Found existing instance, reusing it..."
    fi
elif [ $X == 0 ]; then
    echo "Creating instance: $INSTANCE_NAME"
    gcloud compute instances create $INSTANCE_NAME \
        --project $GCP_PROJECT \
        --image-family ubuntu-1904 \
        --image-project ubuntu-os-cloud \
        --machine-type $MACHINE_TYPE \
        --preemptible
fi

echo "Copying" $ARTILLERY_YML "to" $REMOTE_YML_PATH
gcloud compute scp --project $GCP_PROJECT --zone $GCP_ZONE $ARTILLERY_YML $INSTANCE_NAME:$REMOTE_YML_PATH

echo "Connecting to instance..."
gcloud compute ssh --project $GCP_PROJECT --zone $GCP_ZONE $INSTANCE_NAME -- \
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

gcloud compute scp --project $GCP_PROJECT --zone $GCP_ZONE $INSTANCE_NAME:$REMOTE_RESULT_PATH $RESULT_PATH
gcloud compute scp --project $GCP_PROJECT --zone $GCP_ZONE $INSTANCE_NAME:$REMOTE_REPORT_PATH $REPORT_PATH

echo "Deleting instance: $INSTANCE_NAME"
gcloud compute instances delete --quiet --project $GCP_PROJECT --zone $GCP_ZONE $INSTANCE_NAME
echo "Instance deleted, have a good day!"
