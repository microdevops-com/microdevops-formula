# microdevops-formula

Microdevops SaltStack Formula:
- app - deploy php-fpm, python or static apps to web servers.
- bulk_log, disk_alert, mysql_queries_log, mysql_replica_checker, notify_devilry, rsnapshot_backup, sysadmws-utils - install and configure sysadmws-utils.
- netdata - setup [netdata](https://github.com/firehol/netdata).
- nginx, php-fpm - setup nginx, php-fpm without apps (prepare for app deploy).
- pillar - ready to use pillar collection.
- pyenv - install pyenv different versions.
- scripts/ci_sudo - scripts to use in running regular Salt states via CI (eg. GitLab).
- softether - install and configure Softether VPN Server.
- ufw_simple - install and configure UFW, helps to keep firewall manageable on hundreds of server simultaneously, extends ufw with nat and raw iptables rules, but UFW is required though.
- users - manage users on Windows servers.
- rancher - prepare hosts for rke kubernetes cluster, rke up/remove, install rancher helm chart into the cluster.
- rabbitmq - setup and manage 3.7+ rabbitmq server and management plugin.
- prometheus - setup prometheus, pushgateway, statsd-exporter in Docker
- grafana - setup grafana in Docker
