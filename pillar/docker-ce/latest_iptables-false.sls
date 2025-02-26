docker-ce:
  version: latest
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
