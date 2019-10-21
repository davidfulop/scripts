# Load testing scripts

## gce-loadtest.sh
Wraps [Artillery.js](https://artillery.io/) by starting a [GCE](https://cloud.google.com/compute/ "Google Compute Engine") instance, copying a vanilla Artillery Yaml config/scenario description file to the instance, running Artillery, then getting the results and report back to the host. Tears down the GCE instance after use. Artillery does not need to be installed locally to use this script.

The script keeps an ssh connection open to the box until the test is finished (or something crashes), you can watch the interim results coming from Artillery.

Language is Bash. Tested on Ubuntu 16.04.

### Usage:
1. Copy the [script](./gce-loadtest.sh) and the load test description Yaml file into the same directory.
2. Run $ chmod +x gce-loadtest.sh
3. Run $ ./gce-loadtest.sh <yml_file_name>

To quickly test the script, you can use [loadtest-example.yml](./loadtest-example.yml) provided in the repo. There are many examples of artillery scenario definitions over the interwebz.
