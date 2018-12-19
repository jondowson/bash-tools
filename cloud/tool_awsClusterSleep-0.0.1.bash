#!/usr/bin/env bash

# ========================================================== script details
scriptName="tool_awsClusterSleep";
scriptVersion="0.0.1";
# author:               jondowson@gmail.com
# date:                 november 2018
# dependencies:
# --> bash-version > 4  for associative arrays
# --> aws-cli           to query aws api - setup locally for access to aws pre-prod account


# ========================================================== domain explanation
# Objective:
# to automate the current manual steps to stop pre-prod servers at weekends to cut down aws bill.

# Manual scenario:

# --> friday 6pm
# [1] stop pre-prod cluster   ---> opscenter rolling stop (via opscenter gui).
# [2] stop Opscenter service  ---> service stop on Opscenter server (manually).
# [3] stop all aws servers    ---> aws console stop (manually).
# --> monday 9am
# [4] start all aws servers   ---> aws console start (manually).
# [5] start opscenter service ---> service start on Opscenter server (manually).
# [5] update opscenter config ---> for cluster (via opscenter gui).
# [6] start pre-prod cluster  ---> opscenter rolling start (via opscenter gui).

# Problem:

# aws is highly likely to assign new ip addresses at stage [4].
# these new ip addresses will need to replace the old ones in dse config files before [6].
# but opscenter lcm does not support allocating dns names and insists on ip addresses.
# for security policy or cost reasons the use of static ips may not be possible.

# Possible approaches:

# [A] assign servers static ip addresses in the AWS console.
# [B] bash script that connects to each server and uses tools such as 'sed' to change ip dependent settings.
# [C] bash script that utilises opscenter api to re-assign these ip values. < ==== THIS SCRIPT !!!!!


# ========================================================== script usage
# Automatic scenario:

# Friday evening - 'sleeping' a cluster:

# --> run this script on the 'jump' server.
# --> $ . tool_awsClusterSleep-x.x.x "stop" "<cluster_name>" "<opsUser>" "<opsPass>" "https or http"
# ----> first using the opscenter api - stop the cluster gracefully.
# ----> then the opscenter service.
# ----> finally stop all the aws instances defined in the array below.
# --> note: <opsUser> is the account with sufficient permissions to stop and start the opscenter service.

# Monday morning - 'awakening' a cluster:

# --> run this script on the 'jump' server - specify http or https depending on opscenter setup.
# --> $ . tool_awsClusterSleep-x.x.x "start" "<cluster_name>" "<opsUser>" "<opsPass>" "https or http"
# ----> first start the aws instances.
# ----> then the opscenter service.
# ----> then use the opscenter service to update the cluster config file with the refreshed ip addresses.
# ----> finally using the opscenter api - start the cluster gracefully.


# ========================================================== functions aws
function stopStartAwsInstances(){
# stop or start aws ec2 instances
mode="${1}"
for key in "${!array_awsId_lcmId[@]}"
do
  lcmId=${array_awsId_lcmId[$key]};
  if [[ "${mode}" == "stop" ]];then
    printf "%s\n" "--> stopping aws instances: ${lcmId}";
    aws ec2 stop-instances --instance-ids ${lcmId};
  else
    printf "%s\n" "--> starting aws instances: ${lcmId}";
    aws ec2 start-instances --instance-ids ${lcmId};
  fi;
done;
};

# ***********************************
function getAwsIps(){
# create array to record ip addresses for each lcmId
for key in "${!array_awsId_lcmId[@]}"
do
  lcmId=${array_awsId_lcmId[$key]};
  printf "%s\n" "--> getting private ip for aws instance: ${key}";
  privIp=$(aws ec2 describe-instances --instance-id ${key} | jq -r '.Reservations[].Instances[].PrivateIpAddress');
  array_lcmId_privIp["${lcmId}"]="${privIp}";
  printf "%s\n" "--> getting public ip for aws instance: ${key}";
  pubIp=$(aws ec2 describe-instances --instance-id ${key} | jq -r '.Reservations[].Instances[].PublicIpAddress');
  array_lcmId_pubIp["${lcmId}"]="${pubIp}";
done;
};


# ========================================================== functions opscenter
function stopStartOpsCluster(){
# call opscenter api to issue a stop or start dse cluster command
opsSessionId="${1}";
clusterName="${2}";
stopStart="${3}";
for key in ${!array_opsIp_lcmApiUrl[@]}
do
  pubIp=${key};
  lcmApiUrl=${array_opsIp_lcmApiUrl[$key]};
  curl -H 'opscenter-session: ${opsSessionId}' ${lcmApiUrl}${cluster_name}/ops/${stopStart}/${pubIp};
done;
};

# ***********************************
function opsServiceCommands(){
# issue cluster stop, start or status commands via opscenter api
cmdOps="${1}";
for key in ${!array_lcmId_pubIp[@]}
do
  lcmId=${key};
  pubIp=${array_lcmId_pubIp[$key]};
  if [[ "${pubIp}" != "" ]]; then
    echo ${opsPass} | ssh -tt ${opsUser}@${pubIp} "${cmdOps}";
  fi;
done;
};

# ***********************************
function defineOpsConnectArray(){
# create array to record the api endpoint url for the opscenter public ip
for key in ${!array_lcmId_pubIp[@]}
do
  lcmId=${key};
  pubIp=${array_lcmId_pubIp[$key]};
  if [[ "${pubIp}" != "" ]]; then
    if [[ "${opsSsl}" == "false" ]];then
      lcmApiUrl="http://${pubIp}:8888/";
    else
      lcmApiUrl="https://${pubIp}:8443/";
    fi;
    array_opsIp_lcmApiUrl["${pubIp}"]="${lcmApiUrl}";
  fi;
done;
};

# ***********************************
function getOpsSessionId(){
# get an opscenter session id to authenticate with for api calls
printf "%s\n" "...retrieving sessionId for lcm api";
for key in ${!array_opsIp_lcmApiUrl[@]}
do
  opsIp=${key};
  lcmApiUrl=${array_opsIp_lcmApiUrl[$key]};
done;
sessionId=$(curl -X POST -d '{"username":"${opsUser}","password":"${opsPass}"}' '${lcmApiUrl}login');
printf "%s" "${sessionId}";
};

# ***********************************
function updateDseConfigsPrivIps(){
# for a given lcm cluster-id, update its config file with refreshed private ip
opsSessionId="${1}";
for key in ${!array_lcmId_privIp[@]}
do
  lcmId=${key};
  privIp=${array_lcmId_privIp[$key]};
  printf "%s\n" "...updating lcm node: ${lcmId} to use private_ip: ${privIp}";
  curl -H 'opscenter-session: ${opsSessionId}' \
      -X POST -d '{"listen-address": "${privIp}", \
      "native-transport-address": "${privIp}", \
      "native-transport-broadcast-address": "${privIp}", \
      "broadcast-address": "${privIp}"}' \
      ${lcmApiUrl}api/v2/lcm/nodes/${lcmId};
done;
};

# ***********************************
function updateDseConfigsPubIps(){
# for a given lcm cluster-id, update its config file with refreshed public ip
opsSessionId="${1}";
for key in ${!array_lcmId_pubIp[@]}
do
  lcmId=${key};
  pubIp=${array_lcmId_pubIp[$key]};
  printf "%s\n" "...updating lcm node: ${lcmId} to use public_ip: ${pubIp}";
  curl -H 'opscenter-session: ${opsSessionId}' \
      -X POST -d '{"listen-address": "${pubIp}", \
      "native-transport-address": "${pubIp}", \
      "native-transport-broadcast-address": "${pubIp}", \
      "broadcast-address": "${pubIp}"}' \
      ${lcmApiUrl}api/v2/lcm/nodes/${lcmId};
done;
};


# ================================================== functions utility
function timecount(){
# display a timecount on screen as an opportunity to exit script
min=0;
sec=${1};
message=${2};
printf "%s\n" "${2}";
while [ $min -ge 0 ]; do
      while [[ $sec -ge 0 ]]; do
          echo -ne "00:0$min:$sec\033[0K\r";
          sec=$((sec-1));
          sleep 1;
      done;
      sec=59;
      min=$((min-1));
done;
};

# ***********************************
function displayFormatting(){
# Setup colors and text effects
black=`tput setaf 0`;
red=`tput setaf 1`;
green=`tput setaf 2`;
yellow=`tput setaf 3`;
blue=`tput setaf 4`;
magenta=`tput setaf 5`;
cyan=`tput setaf 6`;
white=`tput setaf 7`;
b=`tput bold`;
u=`tput sgr 0 1`;
ul=`tput smul`;
xl=`tput rmul`;
stou=`tput smso`;
xtou=`tput rmso`;
reverse=`tput rev`;
reset=`tput sgr0`;
pipe=${b}${green}\|\|${reset}
tick="$(printf '\u2705')";
cross="$(printf '\u274c')";
task="$(printf '\u2692\n')";
u="_";
};

# ***********************************
function confirmInstanceState(){
for key in "${!array_awsId_lcmId[@]}"
do
  instanceState=$(aws ec2 describe-instance-status  --output text --instance-ids ${key} --query '{instanceState:InstanceStatuses[*].InstanceState.Name}');
  printf "%s\n" "The status of instance id ${key} is: ${instanceState}";
done;
};


# ================================================== functions main
function stopAws(){
getAwsIps;
defineOpsConnectArray;
opsSessionId=$(getOpsSessionId);
stopStartOpsCluster "${opsSessionId}" "${clusterName}" "stop";
opsServiceCommands "${cmdOpsStop}";
stopStartAwsInstances "${mode}";
};

# ***********************************
function startAws(){
stopStartAwsInstances "${mode}";
getAwsIps;
opsServiceCommands "${cmdOpsStop} && ${cmdOpsStart}";
defineOpsConnectArray;
opsSessionId=$(getOpsSessionId);
updateDseConfigsPrivIps "$(opsSessionId)";
stopStartOpsCluster "${opsSessionId}" "${clusterName}" "start";
};


# ================================================== script setup
# [1] handle incoming variables
mode="${1}";
clusterName="${2}";
opsUser="${3}";
opsPass="${4}";
opsSsl="${5}";
# [2] declare 'globally' associative arrays used by script
declare -A array_awsId_lcmId;
declare -A array_lcmId_privIp;
declare -A array_lcmId_pubIp;
declare -A array_opsIp_lcmApiUrl;
# [3] define the mappings between aws instanceId and the lcm id
array_awsId_lcmId["i-"]="68f598d7-1f4c-4013-ae7a-438c4736bd78";
array_awsId_lcmId["i-"]="d697133c-e70b-48c3-a5b8-e8a06f705c27";
array_awsId_lcmId["i-"]="c2f74bf1-a120-42e7-9be9-e673e18d6d10";
array_awsId_lcmId["i-"]="2c1fafe3-1cb3-4f15-b5b1-ce64454e55ec";
array_awsId_lcmId["i-"]="3a7f77fb-221d-4458-a24f-b30535312054";
array_awsId_lcmId["i-"]="7f7c2c03-dd04-40ec-845d-c743a460676a";
# [4] pre-canned commands
cmdOpsStart="sudo service opscenterd start";
cmdOpsStop="sudo service opscenterd stop";
cmdOpsStatus="sudo service opscenterd status";


# ================================================== script start
# check for bash version > 4
if [[ $BASH_VERSINFO < 4 ]]; then
  if [[ $BASH_UPGRADE_ATTEMPTED != 1 ]]; then
    export BASH_UPGRADE_ATTEMPTED=1;
    export PATH=/usr/local/bin:"$PATH":/bin;
    exec "$(which bash)" --noprofile "$0" """$@""";
  else
    printf "%s\n" "Script requires bash version > 4 to support associative arrays!";
    exit 1;
  fi;
else
  :;
fi;
displayFormatting;
clear;
printf "%s\t%s\n"   "${cyan}script:" "${yellow}${scriptName}-${scriptVersion}";
printf "%s\t%s\n\n" "${cyan}about:"  "${yellow}script to stop dse cluster and put its aws servers into a stop state${reset}";
if [[ "${mode}" == "stop" ]];then
  printf "%s\n\n" "Running script to stop aws instances";
  printf "%s\n\n" "--> make sure you have first stopped the cluster using the opscenter gui!!";
  timecount "10" "Hit <ctrl-c> to stop or leave to continue...";
  stopAws;
  printf "%s\n\n" "Verifying instance state using aws api:";
  confirmInstanceState;
  printf "%s\n" "Script has finished.";
  exit 0;
elif [[ "${mode}" == "start" ]];then
  printf "%s\n\n" "Running script to start aws instances";
  startAws;
  printf "%s\n\n" "Verifying instance state using aws api:";
  confirmInstanceState;
  printf "%s\n" "Script has finished.";
  exit 0;
else
  printf "%s\n" "--> You have not passed a valid option!!";
  printf "%s\n" "--> either 'stop' or 'start'";
  exit 1;
fi;
