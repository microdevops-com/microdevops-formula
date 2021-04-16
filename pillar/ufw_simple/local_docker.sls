ufw_simple:
  enabled: True
  logging: 'off'
  allow:
    local_docker:
      proto: 'tcp'
      from:
        local_docker: '172.16.0.0/12'
