#!/bin/bash

# Read command line arguments
while [[ "$#" -gt 0 ]]; do case $1 in
  --jsm) jsm=1 ;;
  --small) small=1 ;;
  --force)
   if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
     force=1
     version=${2}
     shift
   else
     force=1
   fi
   ;;
  *) echo "Unknown parameter passed: $1"; exit 1;;
esac; shift; done

if [[ ! $(systemctl status jira) ]]; then
 echo "The Jira service was not found on this host." \
 "Please make sure you are running this script on a host that is running Jira."
 exit 1
fi

###################    Variables section         ###################
# Command to install psql client for Amazon Linux 2.
# In case of different distributive, please adjust accordingly or install manually.
INSTALL_PSQL_CMD="amazon-linux-extras install -y postgresql11"

# DB config file location (dbconfig.xml)
DB_CONFIG="/var/atlassian/application-data/jira/dbconfig.xml"

# Depending on Jira installation directory
JIRA_CURRENT_DIR="/opt/atlassian/jira-software/current"
START_JIRA="${JIRA_CURRENT_DIR}/bin/start-jira.sh"
CATALINA_PID_FILE="${JIRA_CURRENT_DIR}/work/catalina.pid"
JIRA_SETENV_FILE="${JIRA_CURRENT_DIR}/bin/setenv.sh"
JIRA_VERSION_FILE="/media/atl/jira/shared/jira-software.version"
SHUT_DOWN_TOMCAT="${JIRA_CURRENT_DIR}/bin/shutdown.sh"

# DB admin user name, password and DB name
JIRA_DB_NAME="jira"
JIRA_DB_USER="postgres"
JIRA_DB_PASS="Password1!"

# Jira/JSM supported versions

SUPPORTED_JIRA_VERSIONS=(8.5.15 8.13.8)
SUPPORTED_JSM_VERSIONS=(4.5.15 4.13.7)

SUPPORTED_VERSIONS=("${SUPPORTED_JIRA_VERSIONS[@]}")
# JSM section
if [[ ${jsm} == 1 ]]; then
  JIRA_CURRENT_DIR="/opt/atlassian/jira-servicedesk/current"
  JIRA_SETENV_FILE="${JIRA_CURRENT_DIR}/bin/setenv.sh"
  JIRA_VERSION_FILE="/media/atl/jira/shared/jira-servicedesk.version"
  SUPPORTED_VERSIONS=("${SUPPORTED_JSM_VERSIONS[@]}")
fi

JIRA_VERSION=$(sudo su jira -c "cat ${JIRA_VERSION_FILE}")
if [[ -z "$JIRA_VERSION" ]]; then
  echo "ERROR: Failed to get Jira version. If your application type is JSM use flag '--jsm'." \
       "Otherwise check if JIRA_VERSION_FILE variable (${JIRA_VERSION_FILE})" \
       "has a valid file path of the Jira version file or set your Cluster JIRA_VERSION explicitly."
  exit 1
fi
echo "Jira Version: ${JIRA_VERSION}"

# Datasets AWS bucket and db dump name
DATASETS_AWS_BUCKET="https://centaurus-datasets.s3.amazonaws.com/jira"
if [[ ${jsm} == 1 ]]; then
  DATASETS_AWS_BUCKET="https://centaurus-datasets.s3.amazonaws.com/jsm"
fi
DATASETS_SIZE="large"
if [[ ${jsm} == 1 && ${small} == 1 ]]; then
  # Only JSM supports "small" dataset
  DATASETS_SIZE="small"
fi
DB_DUMP_NAME="db.dump"
DB_DUMP_URL="${DATASETS_AWS_BUCKET}/${JIRA_VERSION}/${DATASETS_SIZE}/${DB_DUMP_NAME}"

###################    End of variables section  ###################

# Check if Jira version is supported
if [[ ! "${SUPPORTED_VERSIONS[*]}" =~ ${JIRA_VERSION} ]]; then
  echo "Jira Version: ${JIRA_VERSION} is not officially supported by Data Center App Performance Toolkit."
  echo "Supported Jira Versions: ${SUPPORTED_VERSIONS[*]}"
  echo "If you want to force apply an existing datasets to your Jira, use --force flag with version of dataset you want to apply:"
  echo "e.g. ./populate_db.sh --force 8.5.0"
  echo "!!! Warning !!! This may break your Jira instance."
  # Check if --force flag is passed into command
  if [[ ${force} == 1 ]]; then
    # Check if passed Jira version is in list of supported
    if [[ "${SUPPORTED_VERSIONS[*]}" =~ ${version} ]]; then
      DB_DUMP_URL="${DATASETS_AWS_BUCKET}/${version}/${DATASETS_SIZE}/${DB_DUMP_NAME}"
      echo "Force mode. Dataset URL: ${DB_DUMP_URL}"
      # If there is no DOWNGRADE_OPT - set it
      DOWNGRADE_OPT="Djira.downgrade.allowed=true"
      if sudo su jira -c "! grep -q ${DOWNGRADE_OPT} $JIRA_SETENV_FILE"; then
        sudo sed -i "s/JVM_SUPPORT_RECOMMENDED_ARGS=\"/&-${DOWNGRADE_OPT} /" "${JIRA_SETENV_FILE}"
        echo "Flag -${DOWNGRADE_OPT} was set in ${JIRA_SETENV_FILE}"
      fi
    else
      LAST_DATASET_VERSION=${SUPPORTED_VERSIONS[${#SUPPORTED_VERSIONS[@]}-1]}
      DB_DUMP_URL="${DATASETS_AWS_BUCKET}/$LAST_DATASET_VERSION/${DATASETS_SIZE}/${DB_DUMP_NAME}"
      echo "Specific dataset version was not specified after --force flag, using the last available: ${LAST_DATASET_VERSION}"
      echo "Dataset URL: ${DB_DUMP_URL}"
    fi
  else
    # No force flag
    exit 1
  fi
fi

echo "!!! Warning !!!"
echo # move to a new line
echo "This script restores Postgres DB from SQL DB dump for Jira DC created with AWS Quickstart defaults."
echo "You can review or modify default variables in 'Variables section' of this script."
echo # move to a new line
echo "Variables:"
echo "JIRA_CURRENT_DIR=${JIRA_CURRENT_DIR}"
echo "DB_CONFIG=${DB_CONFIG}"
echo "JIRA_DB_NAME=${JIRA_DB_NAME}"
echo "JIRA_DB_USER=${JIRA_DB_USER}"
echo "JIRA_DB_PASS=${JIRA_DB_PASS}"
echo "DB_DUMP_URL=${DB_DUMP_URL}"
echo # move to a new line
read -p "I confirm that variables are correct and want to proceed (y/n)?  " -n 1 -r
echo # move to a new line
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Script was canceled."
  exit 1
fi