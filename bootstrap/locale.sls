{% if pillar["bootstrap"] is defined and "locale" in pillar["bootstrap"] %}
bootstrap_locale:

  {% if pillar["bootstrap"]["locale"]["locale"] == "en_US.UTF-8" and grains["os"] in ["CentOS", "RedHat"] and (grains["osmajorrelease"]|int == 6 or grains["osmajorrelease"]|int == 7) %}
  cmd.run:
    - name: "localedef --no-archive -v -c -i en_US -f UTF-8 C.UTF-8 || true"

  file.managed:
    - name: /etc/sysconfig/i18n
    - contents: |
        LANG="C.UTF-8"
        LC_ALL="C.UTF-8"

  {% else %}
  locale.present:
    - name: "{{ pillar["bootstrap"]["locale"]["locale"] }} {{ pillar["bootstrap"]["locale"]["charset"] }}"

  cmd.run:
    - name: /usr/sbin/update-locale LANG={{ pillar["bootstrap"]["locale"]["locale"] }}

  {% endif %}

{% endif %}
