{% if pillar["jitsi"] is defined and pillar["acme"] is defined %}
{% set acme = pillar['acme'].keys() | first %}

acme_cert_verify_and_issue:
  cmd.run:
    - shell: /bin/bash
    - name: "/opt/acme/home/{{ acme }}/verify_and_issue.sh jitsi {{ pillar["jitsi"]["domain"] }}"

jitsi_data_dirs:
  file.directory:
    - names:
      - /opt/jitsi/{{ pillar["jitsi"]["domain"] }}/config/web
      - /opt/jitsi/{{ pillar["jitsi"]["domain"] }}/config/transcripts
      - /opt/jitsi/{{ pillar["jitsi"]["domain"] }}/config/prosody/config
      - /opt/jitsi/{{ pillar["jitsi"]["domain"] }}/config/prosody/prosody-plugins-custom
      - /opt/jitsi/{{ pillar["jitsi"]["domain"] }}/config/jicofo
      - /opt/jitsi/{{ pillar["jitsi"]["domain"] }}/config/jvb
      - /opt/jitsi/{{ pillar["jitsi"]["domain"] }}/config/jigasi
      - /opt/jitsi/{{ pillar["jitsi"]["domain"] }}/config/jibri
    - makedirs: True

docker_network:
  docker_network.present:
    - name: jitsi

jitsi_frontend_image:
  cmd.run:
    - name: docker pull {{ pillar["jitsi"]["web"]["image"] }}

jitsi_xmpp_server_image:
  cmd.run:
    - name: docker pull {{ pillar["jitsi"]["prosody"]["image"] }}

jitsi_focus_component_image:
  cmd.run:
    - name: docker pull {{ pillar["jitsi"]["jicofo"]["image"] }}

jitsi_video_bridge_image:
  cmd.run:
    - name: docker pull {{ pillar["jitsi"]["jvb"]["image"] }}

jitsi_frontend_container:
  docker_container.running:
    - name: jitsi-web-{{ pillar["jitsi"]["domain"] }}
    - image: {{ pillar["jitsi"]["web"]["image"] }}
    - detach: True
    - restart_policy: unless-stopped
    - binds:
      - /opt/jitsi/{{ pillar["jitsi"]["domain"] }}/config/web:/config
      - /opt/jitsi/{{ pillar["jitsi"]["domain"] }}/config/web/crontabs:/var/spool/cron/crontabs
      - /opt/jitsi/{{ pillar["jitsi"]["domain"] }}/config/transcripts:/usr/share/jitsi-meet/transcripts
      - /opt/acme/cert/jitsi_{{ pillar["jitsi"]["domain"] }}_fullchain.cer:/config/keys/cert.crt
      - /opt/acme/cert/jitsi_{{ pillar["jitsi"]["domain"] }}_key.key:/config/keys/cert.key
    - publish:
      - 80:80/tcp
      - 443:443/tcp
    - networks:
      - jitsi
    - environment:
    {%- for var_key, var_val in pillar["jitsi"]["web"]["env_vars"].items() %}
      - {{ var_key }}: {{ var_val }}
    {%- endfor %}

jitsi_xmpp_server_container:
  docker_container.running:
    - name: jitsi-prosody-{{ pillar["jitsi"]["domain"] }}
    - image: {{ pillar["jitsi"]["prosody"]["image"] }}
    - detach: True
    - restart_policy: unless-stopped
    - binds:
      - /opt/jitsi/{{ pillar["jitsi"]["domain"] }}/config/prosody/config:/config
      - /opt/jitsi/{{ pillar["jitsi"]["domain"] }}/config/prosody/prosody-plugins-custom:/prosody-plugins-custom
    - ports:
      - 5222
      - 5347
      - 5280
    - networks:
      - jitsi:
        - aliases:
          - xmpp.meet.jitsi
    - environment:
    {%- for var_key, var_val in pillar["jitsi"]["prosody"]["env_vars"].items() %}
      - {{ var_key }}: {{ var_val }}
    {%- endfor %}

jitsi_focus_component_container:
  docker_container.running:
    - name: jitsi-jicofo-{{ pillar["jitsi"]["domain"] }}
    - image: {{ pillar["jitsi"]["jicofo"]["image"] }}
    - detach: True
    - restart_policy: unless-stopped
    - binds:
      - /opt/jitsi/{{ pillar["jitsi"]["domain"] }}/config/jicofo:/config
    - publish:
      - 127.0.0.1:8888:8888
    - networks:
      - jitsi
    - environment:
    {%- for var_key, var_val in pillar["jitsi"]["jicofo"]["env_vars"].items() %}
      - {{ var_key }}: {{ var_val }}
    {%- endfor %}
    - require:
      - docker_container: jitsi-prosody-{{ pillar["jitsi"]["domain"] }}

jitsi_video_bridge_container:
  docker_container.running:
    - name: jitsi-jvb-{{ pillar["jitsi"]["domain"] }}
    - image: {{ pillar["jitsi"]["jvb"]["image"] }}
    - detach: True
    - restart_policy: unless-stopped
    - binds:
      - /opt/jitsi/{{ pillar["jitsi"]["domain"] }}/config/jvb:/config
    - publish:
      - 10000:10000/udp
      - 127.0.0.1:8080:8080
    - networks:
      - jitsi
    - environment:
    {%- for var_key, var_val in pillar["jitsi"]["jvb"]["env_vars"].items() %}
      - {{ var_key }}: {{ var_val }}
    {%- endfor %}
    - require:
      - docker_container: jitsi-prosody-{{ pillar["jitsi"]["domain"] }}

  {% if pillar["jitsi"]["jibri"] is defined %}
snd_aloop_module_enable:
  pkg.installed:
    - pkgs:
      - build-essential
      - linux-generic
  cmd.run:
    - name: modprobe snd-aloop
  file.replace:
    - name: /etc/modules
    - pattern: '^snd-aloop$'
    - repl: snd-aloop
    - append_if_not_found: True
jitsi_broadcasting_infrastructure_container:
  docker_container.running:
    - name: jitsi-jibri-{{ pillar["jitsi"]["domain"] }}
    - image: {{ pillar["jitsi"]["jibri"]["image"] }}
    - detach: True
    - restart_policy: unless-stopped
    - binds:
      - /opt/jitsi/{{ pillar["jitsi"]["domain"] }}/config/jibri:/config
    - networks:
      - jitsi
    - cap_add:
      - SYS_ADMIN
    - shm_size: '2gb'
    - environment:
    {%- for var_key, var_val in pillar["jitsi"]["jibri"]["env_vars"].items() %}
      - {{ var_key }}: {{ var_val }}
    {%- endfor %}
    - require:
      - docker_container: jitsi-jicofo-{{ pillar["jitsi"]["domain"] }}
  {% endif %}
{% endif %}
