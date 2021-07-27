wget https://raw.githubusercontent.com/atlassian/dc-app-performance-toolkit/jira/dca-968-run-db-dump-and-attachments-in-parallel/app/util/jira/populate_db_variables.sh
wget https://raw.githubusercontent.com/atlassian/dc-app-performance-toolkit/jira/dca-968-run-db-dump-and-attachments-in-parallel/app/util/jira/upload_attachments_variables.sh

source populate_db_variables.sh
wget https://raw.githubusercontent.com/atlassian/dc-app-performance-toolkit/jira/dca-968-run-db-dump-and-attachments-in-parallel/app/util/jira/populate_db.sh && chmod +x populate_db.sh

source upload_attachments_variables.sh
wget https://raw.githubusercontent.com/atlassian/dc-app-performance-toolkit/jira/dca-968-run-db-dump-and-attachments-in-parallel/app/util/jira/upload_attachments.sh && chmod +x populate_db.sh

./populate_db.sh 2>&1 | tee -a populate_db.log &
./upload_attachments.sh 2>&1 | tee -a upload_attachments.log &