# Logs and debug
```
tail -F /var/log/nginx/alerta.error.log
tail -F /opt/alerta/alerta/uwsgi.log
tail -F /opt/alerta/alerta/alertad.log

su - alerta
/opt/alerta/alerta/venv/bin/uwsgi --ini /etc/uwsgi/sites/alerta.ini # should not detach
```

# Tuning

## UWSGI
Check
```
processes = 20
listen = 1000
```
in pillar and deploy. Higher alert rate requires higher values.

You can get errors like
```
connect() to unix:/tmp/uwsgi-alerta.sock failed (11: Resource temporarily unavailable) while connecting to upstream
```
if values are not high enough.

You can watch `TIME_WAIT` count in netstat to make decision on values.
```
watch -n 0.2 ./watch.sh
```

`watch.sh`:
```
#!/bin/bash
netstat -ant | awk '{print $6}' | sort | uniq -c | sort -n
```

## sysctl
High uwsgi values require sysctl tuning. You can use predefined pillar:
```
    - sysctl.somaxconn-backlog-8192
    - sysctl.netdev-backlog-8192
    - sysctl.net-mem-425984
```

If you are using alerta inside LXD, add pillar above to the host and
```
    - sysctl.somaxconn-backlog-8192
```
to the container as well.

# References
- http://docs.alerta.io/en/latest/gettingstarted/tutorial-1-deploy-alerta.html#tutorial-1
