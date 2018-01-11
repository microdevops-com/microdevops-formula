pkg:
  sysadmws-utils:
    when: 'PKG_PKG'
    states:
{% if grains['os'] in ['Ubuntu', 'Debian'] and not grains['oscodename'] in ['karmic'] %}
      - pkgrepo.managed:
          1:
            - file: /etc/apt/sources.list.d/sysadmws.list
            - name: 'deb https://repo.sysadm.ws/sysadmws-apt/ any main'
            - keyid: 2E7DCF8C
            - keyserver: keyserver.ubuntu.com
      - pkg.latest:
          1:
            - refresh: True
            - pkgs:
                - sysadmws-utils
{% else %}
  {%- if grains['osfinger'] in ['CentOS-6'] %}
      - pkg.installed:
          1:
            - pkgs:
                - python34
                - python34-PyYAML
                - python34-jinja2
  {%- endif %}
  {%- if grains['oscodename'] in ['karmic'] %}
      - pkg.installed:
          1:
            - pkgs:
                - python2.6
                - python-jinja2
                - python-yaml
  {%- endif %}
      - cmd.run:
          1:
            - name: 'rm -f /root/sysadmws-utils.tar.gz'
            - runas: 'root'
          2:
            - name: 'cd /root && wget --no-check-certificate https://repo.sysadm.ws/tgz/sysadmws-utils.tar.gz'
            - runas: 'root'
          3:
            - name: 'tar zxf /root/sysadmws-utils.tar.gz -C /'
            - runas: 'root'
  {%- if grains['osfinger'] in ['CentOS-6'] %}
          4:
            - name: 'sed -i "1s_.*_#!/usr/bin/python3.4_" /opt/sysadmws-utils/notify_devilry/notify_devilry.py'
            - runas: 'root'
  {%- endif %}
{% endif %}
      - file.managed:
          '/opt/sysadmws-utils/notify_devilry/notify_devilry.yaml.jinja':
            - source: 'salt://pkg/files/sysadmws-utils/notify_devilry.yaml.jinja'
            - mode: 0600
      - module.run:
          1:
            - name: state.sls
            - mods: disk_alert.disk_alert
