Most pillars can be used from here.
But you need to add some local:

```
# Optional hosts to fping
netdata:
  fpinger_hosts: '8.8.8.8 8.8.4.4 my-some-host.example.com'

# Mandatory
# You can generate API keys, with the linux command: uuidgen
netdata:
  registry: 'http://your-netdata-central-server.example.com:19999'
  central_server: 'your-netdata-central-server.example.com'
  api_key: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
```
