# Docker pinned to an exact release: applying docker-ce never upgrades (and so never restarts)
# the daemon behind your back. Bump deliberately by switching to a newer pinned file.
# Docker's apt versions carry a 5: epoch - it must be part of the pin. The file name uses
# underscores because dots are path separators in pillar top files.
docker-ce:
  version: '5:29.1.4'
  daemon_json: |
    {
            "iptables": false,
            "default-address-pools": [ {"base": "172.16.0.0/12", "size": 24} ],
            "log-driver": "json-file",
            "log-opts": {
                    "max-size": "1G",
                    "max-file": "5",
                    "compress": "true"
            }
    }
