{% if pillar["memcached"] is defined %} 

memcached-pkg:
  pkg.installed:
    - name: memcached

  {%- for instance, parameters in pillar["memcached"]["instances"].items() %}

    {%- if instance == "main" %}
      {%- set filename = "/etc/systemd/system/memcached.service" %}
      {%- set service = "memcached" %}
    {%- else %}
      {%- set filename = "/etc/systemd/system/memcached-" ~ instance ~ ".service" %}
      {%- set service = "memcached-" ~ instance %}
    {%- endif %}

    {%- set systemd_params = {"user": "memcache", "group": "memcache"} %}
    {%- set params = [] %}

    {%- for item in parameters %}
      {%- if item is mapping %}
        {%- for key, value in item.items() %}
          {%- if key not in systemd_params.keys() %}
            {%- do params.extend(["--", key, "=", value, " "]) %}
          {%- else %}
            {%- do systemd_params.update({ key: value }) %}
          {%- endif %}
        {%- endfor %}
      {%- else %}
          {%- do params.extend(["--", item, " "]) %}
      {%- endif %}
    {%- endfor %}


memcached-{{ instance }}-unit:
  file.managed:
    - name: {{ filename }}
    - user: root
    - group: root
    - contents: |
        [Unit]
        Description=The {{ instance }} memcached daemon
        After=network.target
        
        [Service]
        User={{ systemd_params["user"] }}
        Group={{ systemd_params["group"] }}
        ExecStart=/usr/bin/memcached  {{ params|join("") }}
        
        PrivateTmp=true
        ProtectSystem=full
        NoNewPrivileges=true
        PrivateDevices=true
        RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX

        [Install]
        WantedBy=multi-user.target    

memcached-{{ instance }}-systemd-daemon-reload:
  cmd.run:
    - name: systemctl --system daemon-reload
    - onchanges:
      - file: memcached-{{ instance }}-unit

memcached-{{ instance }}-running:
  service.running:
    - name: {{ service }}
    - enable: True
    - full_restart: True
    - watch:
      - file: memcached-{{ instance }}-unit

  {%- endfor %}

{% endif %}
