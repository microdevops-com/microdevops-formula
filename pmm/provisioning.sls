{% if pillar["pmm"] is defined %}
rsync_default_pmm_provisioning:
  cmd.run:
    - name: docker exec -t percona-{{ pillar["pmm"]["name"] }} bash -c 'rsync -avHAX --delete /usr/share/grafana/conf/provisioning/ {{ pillar["pmm"]["gf_path_provisioning"] }}/'

{#
set_pmm_admin_password_for_PMM_versions_prior_to_2.27.0:
  cmd.run:
    - name: docker exec -t percona-{{ pillar["pmm"]["name"] }} bash -c 'grafana-cli --homepath /usr/share/grafana --configOverrides cfg:default.paths.data=/srv/grafana admin reset-admin-password {{ pillar["pmm"]["admin_password"] }}'
#}
set_pmm_admin_password_for_PMM_versions_2.27.0_and_later:
  cmd.run:
    - name: docker exec -t percona-{{ pillar["pmm"]["name"] }} change-admin-password {{ pillar["pmm"]["admin_password"] }}

grafana_config:
  file.managed:
    - name: /opt/pmm/{{ pillar["pmm"]["name"] }}/etc/grafana/grafana.ini
    - user: root
    - group: root
    - mode: 644
    - contents: {{ pillar["pmm"]["config"] | yaml_encode }}
    - makedirs: True 
  {%- if 'notifiers' in pillar['pmm'] %}
grafana_notifiers:
  file.serialize:
    - name: /opt/pmm/{{ pillar["pmm"]["name"] }}{{ pillar["pmm"]["gf_path_provisioning"] }}/notifiers/notifiers.yaml
    - user: root
    - group: root
    - mode: 644
    - show_changes: True
    - create: True
    - merge_if_exists: False
    - formatter: yaml
    - dataset: {{ pillar['pmm']['notifiers'] }}
  {%- endif %}
  {%- if 'datasources' in pillar['pmm'] %}
grafana_datasources:
  file.serialize:
    - name: /opt/pmm/{{ pillar["pmm"]["name"] }}{{ pillar["pmm"]["gf_path_provisioning"] }}/datasources/datasources.yaml
    - user: root
    - group: root
    - mode: 644
    - show_changes: True
    - create: True
    - merge_if_exists: False
    - formatter: yaml
    - dataset: {{ pillar['pmm']['datasources'] }}
  {%- endif %}
  {%- if 'dashboards' in pillar['pmm'] %}
grafana_dashboards_provisioning_config:
  file.serialize:
    - name: /opt/pmm/{{ pillar["pmm"]["name"] }}{{ pillar["pmm"]["gf_path_provisioning"] }}/dashboards/dashboards.yaml
    - user: root
    - group: root
    - mode: 644
    - show_changes: True
    - create: True
    - merge_if_exists: False
    - formatter: yaml
    - dataset: {{ pillar['pmm']['dashboards']['provisioning_config'] }}
    {%- for dashboard in pillar['pmm']['dashboards']['dashboard_definitions'] %}
create dashboard {{ dashboard['path'] }}:
  file.managed:
    - name: /opt/pmm/{{ pillar["pmm"]["name"] }}{{ dashboard['path'] }}
    - source:
        - {{ dashboard['template'] }}
    - template: jinja
    - makedirs: True
    - context: {{ dashboard['context'] }}
    - defaults: {{ pillar['pmm']['dashboards']['dashboard_definitions_defaults'] }}
    {%- endfor %}
  {%- endif %}
restart grafana:
  cmd.run:
    - shell: /bin/bash
    - name: docker exec -t percona-{{ pillar["pmm"]["name"] }} supervisorctl restart grafana

stop grafana:
  cmd.run:
    - shell: /bin/bash
    - name: docker exec -t percona-{{ pillar["pmm"]["name"] }} supervisorctl stop grafana

install_pmm_image_plugins:
  cmd.run:
    - name: docker exec -t percona-{{ pillar["pmm"]["name"] }} bash -ic 'grafana-cli plugins install {{ pillar["pmm"]["plugins"] }}'

start grafana:
  cmd.run:
    - shell: /bin/bash
    - name: docker exec -t percona-{{ pillar["pmm"]["name"] }} supervisorctl start grafana
{%- endif %}
