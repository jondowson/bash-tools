#!/usr/bin/env bash

# ========================================================== script details
scriptName="tool_schemaDataMigration";
scriptVersion="1.0.2";
# author:               jondowson@gmail.com
# date:                 november 2018
# about:
# --> tool to extract/load table[s] schema[s] using cql
# --> tool to extract/load data using dsebulk loader utility (handles collections too!)
# dependencies:
# --> bash-version > 4  for associative arrays
# --> dsbulk loader     to export and import data into dse cluster


# ========================================================== functions schema
function getSourceSchema(){
# connect to source db and retrieve the schema for the specified keyspace.table
for entry in "${!sourceArray[@]}"
do
  table="$entry";
  keyspace="${sourceArray[$entry]}";
  printf "%s\n" "--> from: ${keyspace}.${table} to: schemas/${keyspace}_${table}.cql";
  cqlsh ${source_ip} -u ${source_user} -p ${source_password} -e "describe table "${keyspace}"."${table}"" > schemas/${keypace}_${table}.cql;
  status=$?
  if [[ ${status} != "0" ]]; then
    printf "%s\n" "cqlsh describe ${keyspace}.${table} has failed.";
    exit 1;
  fi;
done;
};

# ***********************************
function loadDestinationSchema(){
# connect to destination db and load the specified keyspace.table
for entry in "${!destinationArray[@]}"
do
  table="$entry";
  keyspace="${destinationArray[$entry]}";
  printf "%s\n" "--> from: schemas/${keyspace}.${table}.cql to: destination db";
  cqlsh ${destination_ip} -u ${destination_user} -p ${destination_password} < "schemas/${keyspace}"."${table}".cql >> logs/cql.log;
  status=$?
  if [[ ${status} != "0" ]]; then
    printf "%s\n" "cqlsh load schema for ${keyspace}.${table} has failed.";
    exit 1;
  fi;
done;
};

# ***********************************
function mapColumns(){
# create a string mapping column titles to a incremental number.
cqlsh ${source_ip} -u ${source_user} -p ${source_password} -e "describe table ${keypace}.${table}";
columnArray=$(cqlsh ${source_ip} -u ${source_user} -p ${source_password} -e "describe table "${keyspace}"."${table}"" | sed -n '/)/q;p' | sed 's/\CREATE.*//g' | sed 's/\PRIMARY.*//g' | awk '{print $1}');
count=0;
for c in $columnArray
do
  field="${count}=$c";
  if [[ ${count} == "0" ]];then
    mapString="${field}";
  else
    mapString="${mapString}, ${field}";
  fi;
  ((count++));
done;
echo ${mapString};
};


# ========================================================== functions data move
function dataLoad(){
# connect to destination db and load the '<keyspace_table>.csv'
for entry in "${!destinationArray[@]}"
do
  table="$entry";
  keyspace="${destinationArray[$entry]}";
  mapping=$(mapColumns);
  file="conf/dsbulk.conf";
  touch ${file};          # if file does not exist, make it.
  > ${file};              # clear any contents in the file
# write a configuration file for the dsbulk load to use
cat << EOF >> ${file}
dsbulk {
   # The name of the connector to use
   connector.name = "csv"
   # CSV field delimiter
   connector.csv.delimiter = "${source_delim}"
   # The keyspace to connect to
   schema.keyspace = "${keyspace}"
   # The table to connect to
   schema.table = "${table}"
   # The field-to-column mapping
   schema.mapping = "${mapping}"
}
EOF
  printf "%s\n" "--> loading: data/${keyspace}.${table}.csv to destination db";
  dsbulk load -url data/"${keyspace}"_"${table}".csv/output-000001.csv -f ${file} -h "${destination_ips}" -u ${source_user} -p ${source_password} -header true;
  status=$?
  if [[ ${status} != "0" ]]; then
    printf "%s\n" "dsbulk load ${keyspace}.${table} has failed.";
    exit 1;
  fi;
done;
};

# ***********************************
function dataUnload(){
# connect to source db and unload the specified keyspace.table to 'data/<keyspace.table>.csv'
for entry in "${!sourceArray[@]}"
do
  table="$entry";
  keyspace="${sourceArray[$entry]}";
  printf "%s\n" "--> from: ${keyspace}.${table} to: data/${keyspace}_${table}.csv/output-000001.csv";
  dsbulk unload -url data/${keyspace}_${table}.csv -k ${keyspace} -t ${table} -h ${source_ips} -u ${source_user} -p ${source_password} -delim ${source_delim} -header true;
  status=$?
  if [[ ${status} != "0" ]]; then
    printf "%s\n" "dsbulk unload ${keyspace}.${table} has failed.";
    exit 1;
  fi;
done;
};


# ========================================================== functions utility
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


# ========================================================== script setup
# [A] define connection settings for source database
source_user="cassandra";
source_password="cassandra";
source_ip="127.0.0.1";        # specify a single source node ip to connect to for cqlsh
source_ips="127.0.0.1";       # specify at least one source node ip (comma separate multiple ips to increase download performance)
source_delim='|';             # pipe is a good choice - commas don't work if table has collections

# [B] define connection settings for destination database
destination_user="cassandra";
destination_password="cassandra";
destination_ip="127.0.0.1";   # specify a single destination node ip to connect to for cqlsh
destination_ips="127.0.0.1";  # specify at least one destination node ip (comma separate multiple ips to increase upload performance)

# [C] define source table and keyspace array --> [table]="keyspace"
declare -A sourceArray;
sourceArray[cyclist_name]="cycling";
# sourceArray[table]="keyspace";
# ... you can add more entries

# [D] define destination table and keyspace array --> [table]="keyspace"
declare -A destinationArray;
destinationArray[cyclist_name]="cycling";
# destinationArray[table]="keyspace";
# ... you can add more entries

# ========================================================== script start
displayFormatting;
clear;
printf "%s\t%s\n"   "${cyan}script:" "${yellow}${scriptName}-${scriptVersion}";
printf "%s\t%s\n\n" "${cyan}about:"  "${yellow}script to extract/load dse table schemas (cqlsh) and extract/load data (Dsbulk)${reset}";
# [1] make these folders if they don't already exist
mkdir -p conf data logs schemas;
# [2] unload data into csv file from keyspace_table
printf "%s\n\n" "${cyan}STAGE 1/4:${reset} Unload data from source db:";
dataUnload;
# [3] run cqlsh command to grab table schema from source db
printf "%s\n" "============================================================================";
printf "%s\n\n" "${cyan}STAGE 2/4:${reset} Get schema(s) from source db:";
getSourceSchema;

# ---> if renaming destination table. stop script here, and amend the schema file name and contents before continuing with steps [4] + [5]

# [4] create table schema on new/existing cluster (option to delete old one + truncate data)
printf "%s\n" "============================================================================";
printf "%s\n\n" "${cyan}STAGE 3/4:${reset} Load schema(s) into destination db:";
loadDestinationSchema;
# [5] load data into destination cluster
printf "%s\n" "============================================================================";
printf "%s\n\n" "${cyan}STAGE 4/4:${reset} Load data from csv(s) into destination db:";
dataLoad;
