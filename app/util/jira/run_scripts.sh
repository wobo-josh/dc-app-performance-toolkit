  wget https://raw.githubusercontent.com/atlassian/dc-app-performance-toolkit/jira/dca-968-run-db-dump-and-attachments-in-parallel/app/util/jira/configuration.sh

  sleep 2s

  source echo -'y' | ${PWD}/configuration.sh


  wget https://raw.githubusercontent.com/atlassian/dc-app-performance-toolkit/jira/dca-968-run-db-dump-and-attachments-in-parallel/app/util/jira/populate_db.sh && chmod +x populate_db.sh
  wget https://raw.githubusercontent.com/atlassian/dc-app-performance-toolkit/jira/dca-968-run-db-dump-and-attachments-in-parallel/app/util/jira/upload_attachments.sh && chmod +x upload_attachments.sh

  sleep 2s

  parallel ::: "echo 'y' | ./populate_db.sh 2>&1 | tee -a populate_db.log" "echo 'y' | ./upload_attachments.sh 2>&1 | tee -a upload_attachments.log"