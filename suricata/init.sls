{%- if pillar["suricata"] is defined %}
add suricata repository:
  cmd.run:
    - name: add-apt-repository ppa:oisf/suricata-stable --yes
    - unless: dpkg -l | grep suricata

log dir create:
    file.directory:
     - name: /var/log/suricata/

install suricata:
  pkg.installed:
    - pkgs: 
      - suricata
      - jq
    - refresh: True

set values in suricata.yaml:
  file.serialize:
    - name: /etc/suricata/suricata.yaml
    - dataset: {{ pillar["suricata"]["config"] }}
    - serializer: yaml
    - merge_if_exists: true

add header to suricata.yaml:
  file.prepend:
    - name: /etc/suricata/suricata.yaml
    - text:
      - '%YAML 1.1'
      - '---'

run suricata-update and service restart:
  cmd.run:
    - name: suricata-update && systemctl restart suricata
{%- endif %}
