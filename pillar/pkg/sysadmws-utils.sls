pkg:
  sysadmws-utils:
    when: 'PKG_PKG'
    states:
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
      - file.managed:
          '/opt/sysadmws-utils/notify_devilry/notify_devilry.yaml.jinja':
            - source: 'salt://pkg/files/sysadmws-utils/notify_devilry.yaml.jinja'
      - module.run:
          1:
            - name: state.sls
            - mods: disk_alert.disk_alert
