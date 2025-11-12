# PMM Agent Setup
```
apt install pmm2-client

mysql -e "CREATE USER 'pmm'@'localhost' IDENTIFIED BY 'XXXXXXXXXXXXXXXXX';"

mysql -e "GRANT SELECT, PROCESS, SUPER, REPLICATION CLIENT, RELOAD ON *.* TO 'pmm'@'localhost';"

mysql -e "FLUSH PRIVILEGES;"

pmm-agent setup --server-address pmm.example.com --server-username admin --server-password YYYYYYYYYYYYYYYYYY --force --server-insecure-tls

pmm-admin add mysql --socket=$(mysql -s -e "select @@socket" | awk 2) --username=pmm --password=XXXXXXXXXXXXXXXXX --query-source=perfschema
pmm-admin add postgresql --username=someuser --password=XXXXXXXXXXXXXXXXX # needs Superuser pmm user, check https://docs.percona.com/percona-monitoring-and-management/2/setting-up/client/postgresql.html
```
