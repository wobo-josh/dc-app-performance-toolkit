#!/bin/bash

echo "Step1: Download msrcync"
# https://github.com/jbd/msrsync
cd ${TMP_DIR}
if [[ -s msrsync ]]; then
  echo "msrsync already downloaded"
else
  sudo su jira -c "wget https://raw.githubusercontent.com/jbd/msrsync/master/msrsync && chmod +x msrsync"
fi

echo "Step2: Download attachments"
sudo su -c "rm -rf ${ATTACHMENTS_TAR}"
ARTIFACT_SIZE_BYTES=$(curl -sI ${ATTACHMENTS_TAR_URL} | grep "Content-Length" | awk {'print $2'} | tr -d '[:space:]')
ARTIFACT_SIZE_GB=$((${ARTIFACT_SIZE_BYTES}/1024/1024/1024))
FREE_SPACE_KB=$(df -k --output=avail "$PWD" | tail -n1)
FREE_SPACE_GB=$((${FREE_SPACE_KB}/1024/1024))
REQUIRED_SPACE_GB=$((5 + ${ARTIFACT_SIZE_GB}))
if [[ ${FREE_SPACE_GB} -lt ${REQUIRED_SPACE_GB} ]]; then
   echo "Not enough free space for download."
   echo "Free space: ${FREE_SPACE_GB} GB"
   echo "Required space: ${REQUIRED_SPACE_GB} GB"
   exit 1
fi;
sudo su jira -c "time wget --progress=dot:giga ${ATTACHMENTS_TAR_URL}"

echo "Step3: Untar attachments to tmp folder"
sudo su -c "rm -rf ${ATTACHMENTS_DIR}"
sudo su jira -c "tar -xzf ${ATTACHMENTS_TAR} --checkpoint=.10000"
if [[ $? -ne 0 ]]; then
  echo "Untar failed!"
  exit 1
fi
echo "Counting total files number:"
sudo su jira -c "find ${ATTACHMENTS_DIR} -type f -print | wc -l"
echo "Deleting ${ATTACHMENTS_TAR}"
sudo su -c "rm -rf ${ATTACHMENTS_TAR}"

echo "Step4: Copy attachments to EFS"
sudo su jira -c "time ./msrsync -P -p 100 -f 3000 ${ATTACHMENTS_DIR} ${EFS_DIR}"
sudo su -c "rm -rf ${ATTACHMENTS_DIR}"

if [[ ${jsm} == 1 ]]; then
  echo "Step5: Copy avatars to EFS"
  sudo su jira -c "time ./msrsync -P -p 100 -f 3000 ${AVATARS_DIR} ${EFS_DIR}"
  sudo su -c "rm -rf ${AVATARS_DIR}"
fi

echo "DCAPT util script execution is finished successfully."
echo  # move to a new line