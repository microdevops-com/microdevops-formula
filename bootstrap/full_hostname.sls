bootstrap_fullhostname_1:
  cmd.run:
    - name: "cat /etc/hostname | grep -q {{ pillar['resolv_domain'] }} && echo 'hostname is already full' || echo $(cat /etc/hostname | tr -d '\n').{{ pillar['resolv_domain'] }} > /etc/hostname"

bootstrap_fullhostname_2:
  cmd.run:
    - name: "hostname $(cat /etc/hostname)"
