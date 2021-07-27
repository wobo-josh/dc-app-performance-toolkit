#!/bin/bash

echo "Step1: Check Postgres Client"
if ! [[ -x "$(command -v psql)" ]]; then
  echo "Install Postgres client"
  sudo su -c "${INSTALL_PSQL_CMD}"
  if [[ $? -ne 0 ]]; then
    echo "Postgres Client was NOT installed."
    echo "Check correctness of install command or install Postgres client manually."
    echo "INSTALL_PSQL_CMD=${INSTALL_PSQL_CMD}"
    exit 1
  fi
else
  echo "Postgres client is already installed"
fi
echo "Current PostgreSQL version is $(psql -V)"

echo "Step2: Get DB Host and check DB connection"
DB_HOST=$(sudo su -c "cat ${DB_CONFIG} | grep 'jdbc:postgresql' | cut -d'/' -f3 | cut -d':' -f1")
if [[ -z ${DB_HOST} ]]; then
  echo "DataBase URL was not found in ${DB_CONFIG}"
  exit 1
fi
echo "DB_HOST=${DB_HOST}"

echo "Check database connection"
PGPASSWORD=${JIRA_DB_PASS} pg_isready -U ${JIRA_DB_USER} -h ${DB_HOST}
if [[ $? -ne 0 ]]; then
  echo "Connection to database failed. Please check correctness of following variables:"
  echo "JIRA_DB_NAME=${JIRA_DB_NAME}"
  echo "JIRA_DB_USER=${JIRA_DB_USER}"
  echo "JIRA_DB_PASS=${JIRA_DB_PASS}"
  echo "DB_HOST=${DB_HOST}"
  exit 1
fi

echo "Step3: Write jira.baseurl property to file"
JIRA_BASE_URL_FILE="base_url"
if [[ -s ${JIRA_BASE_URL_FILE} ]]; then
  echo "File ${JIRA_BASE_URL_FILE} was found. Base url: $(cat ${JIRA_BASE_URL_FILE})."
else
  PGPASSWORD=${JIRA_DB_PASS} psql -h ${DB_HOST} -d ${JIRA_DB_NAME} -U ${JIRA_DB_USER} -Atc \
  "select propertyvalue from propertyentry PE
  join propertystring PS on PE.id=PS.id
  where PE.property_key = 'jira.baseurl';" > ${JIRA_BASE_URL_FILE}
  if [[ ! -s ${JIRA_BASE_URL_FILE} ]]; then
    echo "Failed to get Base URL value from database."
    exit 1
  fi
  echo "$(cat ${JIRA_BASE_URL_FILE}) was written to the ${JIRA_BASE_URL_FILE} file."
fi

echo "Step4: Write jira license to file"
JIRA_LICENSE_FILE="license"
if [[ -s ${JIRA_LICENSE_FILE} ]]; then
  echo "File ${JIRA_LICENSE_FILE} was found. License: $(cat ${JIRA_LICENSE_FILE})."
  else
    PGPASSWORD=${JIRA_DB_PASS} psql -h ${DB_HOST} -d ${JIRA_DB_NAME} -U ${JIRA_DB_USER} -Atc \
    "select license from productlicense;" > ${JIRA_LICENSE_FILE}
    if [[ ! -s ${JIRA_LICENSE_FILE} ]]; then
      echo "Failed to get jira license from database. Check DB configuration variables."
      exit 1
    fi
    echo "$(cat ${JIRA_LICENSE_FILE}) was written to the ${JIRA_LICENSE_FILE} file."
fi

echo "Step5: Stop Jira"
if [[ ${jsm} == 1 ]]; then
  sudo systemctl stop jira
else
  CATALINA_PID=$(pgrep -f "catalina")
  echo "CATALINA_PID=${CATALINA_PID}"
  if [[ -z ${CATALINA_PID} ]]; then
    echo "Jira is not running"
    sudo su -c "rm -rf ${CATALINA_PID_FILE}"
  else
    echo "Stopping Jira"
    if [[ ! -f "${CATALINA_PID_FILE}" ]]; then
      echo "File created: ${CATALINA_PID_FILE}"
      sudo su -c "echo ${CATALINA_PID} > ${CATALINA_PID_FILE}"
    fi
    sudo su -c "${SHUT_DOWN_TOMCAT}"
    COUNTER=0
    TIMEOUT=5
    ATTEMPTS=30
    while [[ "${COUNTER}" -lt "${ATTEMPTS}" ]]; do
      if [[ -z $(pgrep -f "catalina") ]]; then
        echo Jira is stopped
        break
      fi
      echo "Waiting for Jira stop, attempt ${COUNTER}/${ATTEMPTS} at waiting ${TIMEOUT} seconds."
      sleep ${TIMEOUT}
      let COUNTER++
    done
    if [ ${COUNTER} -eq ${ATTEMPTS} ]; then
      echo "Jira stop was not finished in $ATTEMPTS attempts with $TIMEOUT sec timeout."
      echo "Try to rerun script."
      exit 1
    fi
  fi
fi

echo "Step6: Download database dump"
rm -rf ${DB_DUMP_NAME}
ARTIFACT_SIZE_BYTES=$(curl -sI ${DB_DUMP_URL} | grep "Content-Length" | awk {'print $2'} | tr -d '[:space:]')
ARTIFACT_SIZE_GB=$((${ARTIFACT_SIZE_BYTES}/1024/1024/1024))
FREE_SPACE_KB=$(df -k --output=avail "$PWD" | tail -n1)
FREE_SPACE_GB=$((${FREE_SPACE_KB}/1024/1024))
REQUIRED_SPACE_GB=$((5 + ${ARTIFACT_SIZE_GB}))
if [[ ${FREE_SPACE_GB} -lt ${REQUIRED_SPACE_GB} ]]; then
  echo "Not enough free space for download."
  echo "Free space: ${FREE_SPACE_GB} GB"
  echo "Required space: ${REQUIRED_SPACE_GB} GB"
  exit 1
fi
# use computer style progress bar
time wget --progress=dot:giga "${DB_DUMP_URL}"
if [[ $? -ne 0 ]]; then
  echo "Database dump download failed! Pls check available disk space."
  exit 1
fi

echo "Step7: SQL Restore"
echo "Drop database"
PGPASSWORD=${JIRA_DB_PASS} dropdb -U ${JIRA_DB_USER} -h ${DB_HOST} ${JIRA_DB_NAME}
if [[ $? -ne 0 ]]; then
  echo "Drop DB failed."
  exit 1
fi
sleep 5
echo "Create database"
PGPASSWORD=${JIRA_DB_PASS} createdb -U ${JIRA_DB_USER} -h ${DB_HOST} -T template0 -E "UNICODE" -l "C" ${JIRA_DB_NAME}
if [[ $? -ne 0 ]]; then
  echo "Create database failed."
  exit 1
fi
sleep 5
echo "PG Restore"
time PGPASSWORD=${JIRA_DB_PASS} pg_restore --schema=public -v -U ${JIRA_DB_USER} -h ${DB_HOST} -d ${JIRA_DB_NAME} ${DB_DUMP_NAME}
if [[ $? -ne 0 ]]; then
  echo "SQL Restore failed!"
  exit 1
fi

echo "Step8: Update jira.baseurl property in database"
if [[ -s ${JIRA_BASE_URL_FILE} ]]; then
  BASE_URL=$(cat $JIRA_BASE_URL_FILE)
  if [[ $(PGPASSWORD=${JIRA_DB_PASS} psql -h ${DB_HOST} -d ${JIRA_DB_NAME} -U ${JIRA_DB_USER} -c \
    "update propertystring
    set propertyvalue = '${BASE_URL}'
    from propertyentry PE
    where PE.id=propertystring.id
    and PE.property_key = 'jira.baseurl';") != "UPDATE 1" ]]; then
    echo "Couldn't update database jira.baseurl property. Please check your database connection."
    exit 1
  else
    echo "The database jira.baseurl property was updated with ${BASE_URL}"
  fi
else
  echo "The ${JIRA_BASE_URL_FILE} file doesn't exist or empty. Please check file existence or 'jira.baseurl' property in the database."
  exit 1
fi

echo "Step9: Update jira license in database"
if [[ -s ${JIRA_LICENSE_FILE} ]]; then
  LICENSE=$(cat ${JIRA_LICENSE_FILE})
  LICENSE_ID=$(PGPASSWORD=${JIRA_DB_PASS} psql -h ${DB_HOST} -d ${JIRA_DB_NAME} -U ${JIRA_DB_USER} -Atc \
  "select id from productlicense;")
  if [[ -z "${LICENSE_ID}" ]]; then
    echo "License update failed. License id value in the database is empty."
    exit 1
  fi
  if [[ $(PGPASSWORD=${JIRA_DB_PASS} psql -h ${DB_HOST} -d ${JIRA_DB_NAME} -U ${JIRA_DB_USER} -c \
    "update productlicense
    set license = '${LICENSE}'
    where id = '${LICENSE_ID}';") != "UPDATE 1" ]]; then
    echo "Couldn't update database jira license. Please check your database connection."
    exit 1
  else
    echo "The database jira license was updated with ${LICENSE}"
  fi
else
  echo "The ${JIRA_LICENSE_FILE} file doesn't exist or empty. Please check file existence or jira license in the database."
  exit 1
fi

echo "Step10: Start Jira"
if [[ ${jsm} == 1 ]]; then
  sudo systemctl start jira
else
  sudo su jira -c "${START_JIRA}"
fi
rm -rf ${DB_DUMP_NAME}

echo "Step11: Remove ${JIRA_BASE_URL_FILE} file"
sudo rm ${JIRA_BASE_URL_FILE}

echo "Step12: Remove ${JIRA_LICENSE_FILE} file"
sudo rm ${JIRA_LICENSE_FILE}

echo "DCAPT util script execution is finished successfully."
echo # move to a new line

echo "Important: new admin user credentials are admin/admin"
echo "Wait a couple of minutes until Jira is started."