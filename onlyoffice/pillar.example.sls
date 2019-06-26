onlyoffice:
  docker-ce_version: 5:18.09.6
  domain: onlyoffice.example.com # for nginx proxy and its ssl on https://onlyoffice.example.com/
  port: 81 # docker published port, nginx will forward location / to it
  image: onlyoffice/documentserver:latest
  email: mail@example.com
