#!/bin/bash
set -e
set -u

function print_help {
    echo "GCE-loadtest"
    echo "Wraps Artillery.js by starting a GCE instance, copying a vanilla "
    echo "Artillery Yaml config/scenario description file to the instance, "
    echo "running Artillery, then getting the results and report back to the "
    echo "host. Tears down the GCE instance after use. Artillery does not "
    echo "need to be installed locally to use this script."
    echo "Usage:"
    echo "1. Copy the [script](./gce-loadtest.sh) and the load test "
    echo " description Yaml file into the same directory."
    echo "2. Run chmod +x gce-loadtest.sh"
    echo "3. Run ./gce-loadtest.sh [OPTIONS --] <ARTILLERY_YAML>"
    echo "Options:"
    echo "-m|--machine-type <VALUE>"
    echo "    sets the machine type the load testing instance will be "
    echo "    created from. Accepts values listed in the NAME column of the "
    echo "    response from gcloud compute machine-types list --zones <ZONE>, "
    echo "    where <ZONE> is the Availability Zone your local gcloud compute "
    echo "    is set to. Default is n1-highcpu-8."
    echo "-p|--project <VALUE>"
    echo "    sets the GCP project id where the load testing instance will be "
    echo "    created in. Default is whichever project the local gcloud is "
    echo "    set to."
    echo "-z|--zone <VALUE>"
    echo "    sets the compute zone where the load testing instance will be "
    echo "    created in. Default is whichever zone the local gcloud is set to."
    echo "-k|--keep-instance"
    echo "    doesn't delete the instance after the test finished."
    echo "-e|--env-var <KEY=VALUE>"
    echo "    set environment variable"
}

PARAMS=""
MACHINE_TYPE="n1-highcpu-8"
GCP_PROJECT=$(gcloud config get-value project)
GCP_ZONE=$(gcloud config get-value compute/zone)
KEEP_INSTANCE=false
ENV_VAR=""

while :; do
    case $1 in
        -h|-\?|--help)
            print_help
            exit
            ;;
        -m|--machine-type)
            MACHINE_TYPE=$2
            shift 2
            ;;
        -p|--project)
            GCP_PROJECT=$2
            shift 2
            ;;
        -z|--zone)
            GCP_ZONE=$2
            shift 2
            ;;
        -k|--keep-instance)
            KEEP_INSTANCE=true
            shift
            ;;
        -e|--env-var)
            ENV_VAR=$2
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
ARTILLERY_YML=$1
DATE=$(date +"%Y%m%d_%H%M")
LOCAL_RESULT_DIR="./results"
REMOTE_YML_PATH="/tmp/$ARTILLERY_YML"
RESULT_FILE_NAME=$ARTILLERY_YML"_results_"$DATE
RESULT_PATH=$LOCAL_RESULT_DIR"/"$RESULT_FILE_NAME".json"
REPORT_PATH=$LOCAL_RESULT_DIR"/"$RESULT_FILE_NAME".html"
REMOTE_RESULT_PATH="/tmp/"$RESULT_FILE_NAME".json"
REMOTE_REPORT_PATH="/tmp/"$RESULT_FILE_NAME".html"

echo "Using project: $GCP_PROJECT"
echo "Using zone: $GCP_ZONE"

EXISTS=$(gcloud compute instances list --project $GCP_PROJECT \
    --zones $GCP_ZONE | { grep -c $INSTANCE_NAME || true; })
if [ $EXISTS == 1 ]; then
    RUNNING=$(gcloud compute instances describe --project $GCP_PROJECT \
        --zone $GCP_ZONE $INSTANCE_NAME | { grep -c "status: RUNNING" || true; })
    if [ $RUNNING == 0 ]; then
        echo "Instance already created, but not running; script terminating."
        exit 1
    else
        echo "Found existing instance, reusing it..."
    fi
else
    echo "Creating instance: $INSTANCE_NAME"
    gcloud compute instances create $INSTANCE_NAME \
        --project $GCP_PROJECT \
        --zone $GCP_ZONE \
        --image-family ubuntu-1904 \
        --image-project ubuntu-os-cloud \
        --machine-type $MACHINE_TYPE \
        --preemptible
fi

echo "Copying" $ARTILLERY_YML "to" $REMOTE_YML_PATH
gcloud compute scp --project $GCP_PROJECT --zone $GCP_ZONE \
    $ARTILLERY_YML $INSTANCE_NAME:$REMOTE_YML_PATH

echo "Connecting to instance..."
gcloud compute ssh --project $GCP_PROJECT --zone $GCP_ZONE $INSTANCE_NAME -- \
    "echo export $ENV_VAR \
    && echo 'Installing load testing tools...' \
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

gcloud compute scp --project $GCP_PROJECT --zone $GCP_ZONE \
    $INSTANCE_NAME:$REMOTE_RESULT_PATH $RESULT_PATH
gcloud compute scp --project $GCP_PROJECT --zone $GCP_ZONE \
    $INSTANCE_NAME:$REMOTE_REPORT_PATH $REPORT_PATH

if [ $KEEP_INSTANCE = false ]; then
    echo "Deleting instance: $INSTANCE_NAME"
    gcloud compute instances delete --quiet --project $GCP_PROJECT \
        --zone $GCP_ZONE $INSTANCE_NAME
    echo "Instance deleted"
else
    echo "--- INSTANCE $INSTANCE_NAME KEPT ALIVE IN $GCP_PROJECT/$GCP_ZONE ---"
fi
echo "Script finished, have a good day!"
