#!/usr/bin/env bash

scriptName="tool_harvestMetrics";
version="1.3.1";

## author:  jondowson@datastax.com
## about:   run nodetool + dsetool commands and collect output in a pre-defined folder structure.
#  - script user to setup below an array of server ip addresses to execute nodetool / dsetool commands on.
#  - can be set to run multiple times with interval between collections. i.e if collecting stats before,during and after a stress test.
#  - optionally you can collect table stats on 1 or more keyspace.table in the C* db.
#  - script will bring back all harvested stats to the calling machine and (optionally) remove them from the remote machines.

# ========================================================== FUNCTIONS
function identifyOs(){
## about:     identify operating system. Handke Centos/Redhat as well as Ubuntu and Mac.
## example:   call this function and capture reponse.
##            os=$(identifyOs);
OS=$(uname -a);
if [[ ${OS} == *"Darwin"* ]]; then
  os="Mac";
elif [[ ${OS} == *"Ubuntu"* ]]; then
  os="Ubuntu";
elif [[ "$(cat /etc/system-release-cpe)" == *"centos"* ]]; then
  os="Centos";
elif [[ "$(cat /etc/system-release-cpe)" == *"redhat"* ]]; then
  os="Redhat";
else
  os="Unknown";
fi
printf "%s" "${os}";
};

# ***********************
function copyConfigFiles(){
## about:     copy files on server to a defined location.
## example:   call this function and capture reponse.
##            copyConfigFiles;
writeFolder="${1}";
for path in ${!arrayCopyPaths[@]}
do
  cp "${path}"  "${writeFolder}${arrayCopyPaths[$path]}/";
done;
};

# ***********************
function makeFolderStructure(){
targetFolder="${1}";
serverIp="${2}";
dateFolder="${3}";
mkdir -p "${targetFolder}/${serverIp}/${dateFolder}nodetool";
mkdir -p "${targetFolder}/${serverIp}/${dateFolder}nodetool/tableStats";
mkdir -p "${targetFolder}/${serverIp}/${dateFolder}dsetool";
mkdir -p "${targetFolder}/${serverIp}/${dateFolder}conf";
mkdir -p "${targetFolder}/${serverIp}/${dateFolder}conf/cassandra";
mkdir -p "${targetFolder}/${serverIp}/${dateFolder}conf/dse";
mkdir -p "${targetFolder}/${serverIp}/${dateFolder}cqlsh";
mkdir -p "${targetFolder}/${serverIp}/${dateFolder}log";
};

# ***********************
function miscServerStats(){
writeFolder="${1}";
os="$(identifyOs)";
jv=$(java -version  2>&1);
echo "${jv}"                      > ${writeFolder}javaversion;
if [[ "${os}" == "Mac" ]];then
  vm_stat                         > ${writeFolder}vm_stat;
else
  echo "os is: ${os}";
  free -m                         > ${writeFolder}free;
fi;
df -h                             > ${writeFolder}df-h;
cqlsh -e "describe full schema"   > ${writeFolder}cqlsh/describe_schema;
};

# ***********************
function nodetoolServerStats(){
nodetoolCmd="${1}";
writeFolder="${2}";
${nodetoolCmd} proxyhistograms > ${writeFolder}proxyhistograms;
${nodetoolCmd} gossipinfo      > ${writeFolder}gossipinfo;
${nodetoolCmd} tpstats         > ${writeFolder}tpstats;
${nodetoolCmd} cfstats         > ${writeFolder}cfstats;
${nodetoolCmd} gcstats         > ${writeFolder}gcstats;
${nodetoolCmd} info            > ${writeFolder}info;
${nodetoolCmd} status          > ${writeFolder}status;
${nodetoolCmd} version         > ${writeFolder}version;
${nodetoolCmd} netstats        > ${writeFolder}netstats;
${nodetoolCmd} describecluster > ${writeFolder}describecluster;
${nodetoolCmd} compactionstats > ${writeFolder}compactionstats;
};

# ***********************
function nodetoolTableStats(){
nodetoolCmd="${1}";
keyspaceDotTable="${2}";
writeFolder="${3}";
${nodetoolCmd} tablestats      ${keyspaceDotTable} > ${writeFolder}tablestats_${keyspaceDotTable}.txt;
${nodetoolCmd} tablehistograms ${keyspaceDotTable} > ${writeFolder}tablehistograms_${keyspaceDotTable}.txt;
};

# ***********************
function dsetoolServerStats(){
dsetoolCmd="${1}";
writeFolder="${2}";
${dsetoolCmd} node_health --all  > ${writeFolder}node_health;
${dsetoolCmd} ring               > ${writeFolder}ring;
${dsetoolCmd} status             > ${writeFolder}status;
};

# ***********************
function waitForPids(){
## about:     wait for a set of processes to complete. assign status to appropriate array.
## example:   wait for a set of processes during a stage - no parameters need to be passed.
##            BB_lib_network_waitForPids;
for p in $arrayPids
do
  if [[ "${p}" != "local" ]];then
    if wait $p; then
      result=$?;
      if [ "${result}" == "0" ]; then
        arrayPidSuccess+=" ${p}";
      else
        arrayPidFail+=" ${p}";
      fi;
    else
      arrayPidFail+=" ${p}";
    fi;
  fi;
done;
};

# ***********************
function display(){
## about:     display messages based on a simple colour scheme.
## example:   display "Film title:" "Star Wars" with 2 tabs between strings, no newline before the string and one new line to follow.
##            BB_prepare_display_msgColour "INFO-->" "message title:" "message body" "2" "0" "1";
messageType="${1}";
message1="${2}";
message2="${3}";
tab="${4}";
newlinesBefore="${5}";
newlinesAfter="${6}";
tabString="";
newlinesBeforeString="";
newlinesAfterString="";
if [[ "${tab}" != "0" ]];then
  for i in $(seq 1 ${tab});
  do
    tabString="${tabString}\t";
  done;
fi;
if [[ "${newlinesBefore}" != "0" ]];then
  for i in $(seq 1 ${newlinesBefore});
  do
    newlinesBeforeString="${newlinesBeforeString}\n";
  done;
fi;
if [[ "${newlinesAfter}" != "0" ]];then
  for i in $(seq 1 ${newlinesAfter});
  do
    newlinesAfterString="${newlinesAfterString}\n";
  done;
fi;
case ${messageType} in
  "STAGECOUNT" )
                  printf "${newlinesBeforeString}%s${tabString}%s${newlinesAfterString}" "${b}${message1}${reset}" "${b}${message2}${reset}";;
  "TASK==>" )
                  printf "${newlinesBeforeString}%s${tabString}%s${newlinesAfterString}" "${b}${cyan}==> ${message1}${reset}" "${b}${message2}${reset}";;
  "ERROR-->" )
                  printf "${newlinesBeforeString}%s${tabString}%s${newlinesAfterString}" "${b}${red}==> ${message1}" "${yellow}${message2}${reset}";;
  "ALERT-->" )
                  printf "${newlinesBeforeString}%s${tabString}%s${newlinesAfterString}" "${b}${yellow}--> ${message1}${reset}" "${b}${message2}${reset}";;
  "INFO-->" )
                  printf "${newlinesBeforeString}%s${tabString}%s${newlinesAfterString}" "${reset}--> ${message1}" "${message2}${reset}";;
  "INFO-B-->" )
                  printf "${newlinesBeforeString}%s${tabString}%s${newlinesAfterString}" "${b}--> ${message1}${reset}" "${message2}${reset}";;
  "INFO-BY-->" )
                  printf "${newlinesBeforeString}%s${tabString}%s${newlinesAfterString}" "${b}--> ${yellow}${message1}${reset}" "${message2}${reset}";;
  "TICK-->" )
                  printf "${newlinesBeforeString}%s%s${tabString}%s${newlinesAfterString}" "${b}--> ${tick} " "${yellow}${message1}${reset}" "${message2}${reset}";;
  "CROSS-->" )
                  printf "${newlinesBeforeString}%s%s${tabString}%s${newlinesAfterString}" "${b}--> ${cross} " "${yellow}${message1}${reset}" "${message2}${reset}";;
esac;
};

# ***********************
function pidReport(){
if [[ ${arrayPidFail} != "" ]]; then
  for f in ${arrayPidFail[@]}
  do
    display "CROSS-->" "failure:" "${arrayPidDetails[$f]}" "1" "0" "1";
  done;
  for s in ${arrayPidSuccess[@]}
  do
    display "TICK-->" "success:" "${arrayPidDetails[$s]}" "1" "0" "1";
  done;
else
  display "TICK-->" "all servers:" "success" "1" "0" "1";
fi;
};

# ========================================================== SCRIPT SETUP 1/2
# discover script path
scriptPath=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P );

# ***********************
# display formatting
cyan=`tput setaf 6`;
yellow=`tput setaf 3`;
blue=`tput setaf 4`;
b=`tput bold`;
reset=`tput sgr0`;
tick="$(printf '\u2705')";
cross="$(printf '\u274c')";

# ***********************
# define arrays
declare -A array_serverIp;
declare -A arrayCopyPaths;
declare -a array_keyspaceDotTable;
declare -a arrayPids;
declare -a arrayPidSuccess;
declare -a arrayPidFail;
declare -A arrayPidDetails;

# ***********************
# make folder to hold stats from all servers
mkdir -p ${scriptPath}/statsByIp;

# ==========================================================  USER DEFINED SETTINGS
# [1] how many times to collect stats and whether to delete on remote server once retrieved?
#     - set to 1 to collect stats only once.
#     - more than once will put stats in a time stamped sub-folder.
#     - if more than once - set interval time between collections. set a reasonable minimum ~ 10s!
repeatTimes="2";
intervalSeconds="10";
cleanRemoteFolders="true";

# ***********************
# [2] where on servers to create collection folders?
#     - same path will be used for all servers!
targetFolder="~/Desktop/";

# ***********************
# [3] which servers and ssh user to perform stat collection on?
#     - supply at least one ip address and ssh user.
#     - prior to running enable passwordless authentication with ssh-copy-id utility!
array_serverIp["127.0.0.1"]="jondowson";
#array_serverIp[127.0.0.2]="jonsmith";

# ***********************
# [4] location of config + log files to grab?
#     - these paths need to be the same on each server to work!
#     - include name of file at end of path + fill all in!
systemLogPath="/Users/jondowson/Desktop/bash-blocks/installed-blocks/dse/logs/dse-6.0.2_burberry/cassandra/system.log";
debugLogPath="/Users/jondowson/Desktop/bash-blocks/installed-blocks/dse/logs/dse-6.0.2_burberry/cassandra/debug.log";
cassandraYamlPath="/Users/jondowson/Desktop/bash-blocks/installed-blocks/dse/dse-6.0.2_burberry/dse-6.0.2/resources/cassandra/conf/cassandra.yaml";
dseYamlPath="/Users/jondowson/Desktop/bash-blocks/installed-blocks/dse/dse-6.0.2_burberry/dse-6.0.2/resources/dse/conf/dse.yaml";
cassandraEnvPath="/Users/jondowson/Desktop/bash-blocks/installed-blocks/dse/dse-6.0.2_burberry/dse-6.0.2/resources/cassandra/conf/cassandra-env.sh";
# add path to files as keys and folder (path from under the parent ip folder) as destination for the copied file
arrayCopyPaths["${systemLogPath}"]="log";
arrayCopyPaths["${debugLogPath}"]="log";
arrayCopyPaths["${cassandraYamlPath}"]="conf/cassandra";
arrayCopyPaths["${dseYamlPath}"]="conf/cassandra";
arrayCopyPaths["${cassandraEnvPath}"]="conf/dse";

# ***********************
# [5] optionally - do you want to gather tablestats on given keyspace.table?
#     - if not required comment out this section.
#     - if not empty tablestats will be gathered and put into its own subfolder.
array_keyspaceDotTable[0]="system.local";
#array_keyspaceDotTable[1]="keyspace1.table2";

# ***********************
# [6] does nodetool and dsetool require authentication?
#     - set user and password if required.
#     - if not required comment out.
#     - for any given cluster, these should be the same on each node.
#userCassandra="cassandra";
#passwordCassandra="cassandra";

# ========================================================== SCRIPT SETUP 2/2
# calculate length of user defined arrays
array_serverIpLength=${#array_serverIp[@]};
array_keyspaceDotTableLength=${#array_keyspaceDotTable[@]};

# ***********************
# establish nodetool + dsetool commands if auth is used or not.
if [[ "${user}" != "" ]]; then
  nodetoolCmd="nodetool -u ${userCassandra} -pw ${passwordCassandra}";
  dsetoolCmd="dsetool   -u ${userCassandra} -pw ${passwordCassandra}";
else
  nodetoolCmd="nodetool";
  dsetoolCmd="dsetool";
fi;

# ========================================================== SCRIPT RUN
# [1] display title
clear;
printf "%s\n" "*******************************************************************";
printf "%s\n" "${b}${scriptName} - version: ${yellow}${version}${reset}";
printf "%s\n" "${b}${yellow}iterations: ${cyan}${repeatTimes}${reset}";
printf "%s\n" "${b}${yellow}interval:   ${cyan}${intervalSeconds} sec${reset}";
printf "%s\n" "*******************************************************************";

# ***********************
# [2] repeat stat collection the defined x number of times with the defined interval
display "TASK==>" "TASK: collect nodetool + dsetool stats on each server" "" "1" "0" "2";
for run in $(seq 1 ${repeatTimes});
do
  # loop through server array and execute the functions
  for serverIp in "${!array_serverIp[@]}"
  do
    if [ "${repeatTimes}" -gt "1" ];then
      date=$(date '+%Y-%m-%d %H:%M:%S');
      date=$(echo ${date// /_});
      dateFolder="${date}/";
      dateFolderMsg="/${date}/";
    fi;
    serverIp="${serverIp}";
    folderMsg="${yellow}${serverIp}${dateFolderMsg}${reset}";
    userSsh="${array_serverIp[$serverIp]}";
    nodetoolWriteFolder="${targetFolder}/${serverIp}/${dateFolder}nodetool/";
    dsetoolWriteFolder="${targetFolder}/${serverIp}/${dateFolder}dsetool/";
    miscWriteFolder="${targetFolder}/${serverIp}/${dateFolder}";
    printf "%s\n" "${b}--> on server: ${yellow}${serverIp}${reset}";
    printf "%s\n"   "--> ${yellow}creating:${reset}  folder structure (under folder ${folderMsg})";
    printf "%s\n"   "--> ${yellow}nodetool:${reset}  proxyhistograms, tpstats, gcstats and info";
    printf "%s\n"   "--> ${yellow}dsetool:${reset}   node_health and ring";
    printf "%s\n"   "--> ${yellow}cqlsh:${reset}     describe schema";
    printf "%s\n"   "--> ${yellow}java:${reset}      -v";
    printf "%s\n"   "--> ${yellow}disk:${reset}      df-h";
    printf "%s\n"   "--> ${yellow}ram:${reset}       free -m (vmstat on Mac)";
    printf "%s\n"   "--> ${yellow}copy:${reset}      cassandra.yaml, dse.yaml, cassandra-env.sh, debug.log and system.log";
    ssh ${userSsh}@${serverIp} "$(typeset -f); \
    source ~/.bash_profile; \
    makeFolderStructure ${targetFolder} ${serverIp} ${dateFolder}; \
    nodetoolServerStats ${nodetoolCmd}  ${nodetoolWriteFolder}; \
    dsetoolServerStats  ${dsetoolCmd}   ${dsetoolWriteFolder}; \
    miscServerStats     ${miscWriteFolder}; \
    copyConfigFiles     ${miscWriteFolder}" &
    pid=${!};
    printf "%s\n" "--> ${cyan}$pid${reset}";
    details="nodetool + dsetool + misc stats on ${serverIp} with pid ${cyan}$pid${reset}";
    arrayPidDetails["${pid}"]="${details}";
    arrayPids+=" $pid";
    if [ "${array_keyspaceDotTableLength}" -gt 0 ]; then
      tableStatsWriteFolder="${targetFolder}/${serverIp}/${dateFolder}nodetool/tableStats/";
      for keyspaceDotTable in "${array_keyspaceDotTable[@]}"
      do
        printf "%s\n" "--> ${yellow}nodetool:${reset}  tablestats and tablehistograms for ${yellow}${keyspaceDotTable}${reset} ";
        ssh ${userSsh}@${serverIp} "$(typeset -f); \
        source ~/.bash_profile; \
        makeFolderStructure ${targetFolder} ${serverIp} ${dateFolder}; \
        nodetoolTableStats ${nodetoolCmd} ${keyspaceDotTable} ${tableStatsWriteFolder}" &
        pid=${!};
        printf "%s\n" "--> ${cyan}$pid${reset}";
        details="nodetool table stats for ${keyspaceDotTable} on ${serverIp} with pid ${cyan}$pid${reset}";
        arrayPidDetails["${pid}"]="${details}";
        arrayPids+=" $pid";
      done;
    fi;
  done;
  printf "\n%s\n" "${b}--> waiting for all pids on all servers to complete...";
  waitForPids;
  pidReport;
  if [ "${repeatTimes}" -gt "1" ] && [ "${run}" -lt "${repeatTimes}" ]; then
    printf "\n%s\n" "${b}${yellow}..run ${run} of ${repeatTimes} complete, taking interval of: ${cyan}${intervalSeconds} sec${reset}";
    printf "\n%s\n" "*******************************************************************";
    sleep "${intervalSeconds}";
  else
    printf "\n%s\n\n" "${b}${yellow}..run ${run} of ${repeatTimes} complete ${reset}";
  fi;
done;

# ***********************
# [3] loop through server array and retrieve stats folder from each server
printf "%s\n" "*******************************************************************";
display "TASK==>" "TASK: retrieve stats from each server" "" "1" "1" "2";
for serverIp in "${!array_serverIp[@]}"
do
  serverIp="${serverIp}";
  userSsh="${array_serverIp[$serverIp]}";
  printf "%s\n" "${b}--> on server: ${yellow}${serverIp}${reset}";
  scp -r -q -o LogLevel=QUIET ${userSsh}@${serverIp}:${targetFolder}/${serverIp} ${scriptPath}/statsByIp/ &
  pid=${!};
  printf "%s\n" "--> ${cyan}$pid${reset}";
  details="retrieving stats from ${serverIp} with pid ${cyan}$pid${reset}";
  arrayPidDetails["${pid}"]="${details}";
  arrayPids+=" $pid";
done;
printf "\n%s\n" "${b}--> waiting for all pids on all servers to complete...";
waitForPids;
pidReport;

# ***********************
# [4] remove remote stats folders
if [ "${cleanRemoteFolders}" == "true" ]; then
  printf "%s\n" "*******************************************************************";
  display "TASK==>" "TASK: remove stats from each remote server" "" "1" "1" "2";
  for serverIp in "${!array_serverIp[@]}"
  do
    serverIp="${serverIp}";
    userSsh="${array_serverIp[$serverIp]}";
    printf "%s\n" "${b}--> on server: ${yellow}${serverIp}${reset}";
    if [ "${serverIp}" != "" ]; then
      ssh ${userSsh}@${serverIp} "rm -rf ${targetFolder}/${serverIp}";
    fi;
    pid=${!};
    printf "%s\n" "--> ${cyan}$pid${reset}";
    details="remove stats from ${serverIp} with pid ${cyan}$pid${reset}";
    arrayPidDetails["${pid}"]="${details}";
    arrayPids+=" $pid";
  done;
  printf "\n%s\n" "${b}--> waiting for all pids on all servers to complete...";
  waitForPids;
  pidReport;
fi;

# ***********************
printf "\n%s\n" "*******************************************************************";
printf "%s\n"   "${b}--> finished${reset}";
printf "%s\n" "*******************************************************************";
