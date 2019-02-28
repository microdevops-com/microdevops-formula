pkg:
  locale:
    when: 'PKG_PKG'
    states:
{% if grains['os'] in ['CentOS', 'RedHat'] and (grains['osmajorrelease']|int == 6 or grains['osmajorrelease']|int == 7) %}
      - cmd.run:
          1:
            - name: "localedef --no-archive -v -c -i en_US -f UTF-8 C.UTF-8 || true"
      - file.managed:
          1:
            - name: "/etc/sysconfig/i18n"
            - contents: |
                LANG="C.UTF-8"
                LC_ALL="C.UTF-8"
  {%- if grains['osmajorrelease']|int == 7 %}
      - file.symlink:
          1:
            - name: "/usr/share/terminfo/s/screen-256color-bce"
            - target: "/usr/share/terminfo/s/screen-256color"
  {%- endif %}
{% else %}
      - locale.present:
          1:
            - name: "en_US.UTF-8 UTF-8"
      - cmd.run:
          1:
            - name: "/usr/sbin/update-locale LANG=en_US.UTF-8"
{% endif %}
