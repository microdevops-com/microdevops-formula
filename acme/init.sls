{% if pillar["acme"] is defined %}
acme_dirs:
  file.directory:
    - names:
      - /opt/acme/cert
    - makedirs: True

  {%- for acme_acc, acme_params in pillar["acme"].items() %}
acme_acc_dirs_{{ loop.index }}:
  file.directory:
    - names:
      - /opt/acme/{{ acme_acc }}/git
      - /opt/acme/{{ acme_acc }}/home
      - /opt/acme/{{ acme_acc }}/config
      - /opt/acme/home/{{ acme_acc }}
    - makedirs: True

acme_git_{{ loop.index }}:
  git.latest:
    - name: https://github.com/acmesh-official/acme.sh.git
    - target: /opt/acme/{{ acme_acc }}/git
    - force_reset: True
    - force_fetch: True
    - rev: {{ acme_params.get("rev", "master") }}

acme_install_{{ loop.index }}:
  cmd.run:
    - name: /opt/acme/{{ acme_acc }}/git/acme.sh --home /opt/acme/{{ acme_acc }}/home --cert-home /opt/acme/{{ acme_acc }}/cert --config-home /opt/acme/{{ acme_acc }}/config --no-cron --install
    - cwd: /opt/acme/{{ acme_acc }}/git

acme_set_ca_server_{{ loop.index }}:
  cmd.run:
    - name: /opt/acme/{{ acme_acc }}/git/acme.sh --home /opt/acme/{{ acme_acc }}/home --cert-home /opt/acme/{{ acme_acc }}/cert --config-home /opt/acme/{{ acme_acc }}/config --set-default-ca --server {{ acme_params.get("ca_server","letsencrypt") }}
    - cwd: /opt/acme/{{ acme_acc }}/git

    {%- if "post_install_cmd" in acme_params %}
acme_post_install_cmd_{{ loop.index }}:
  cmd.run:
    - name: /opt/acme/{{ acme_acc }}/git/acme.sh --home /opt/acme/{{ acme_acc }}/home --cert-home /opt/acme/{{ acme_acc }}/cert --config-home /opt/acme/{{ acme_acc }}/config {{ acme_params["post_install_cmd"] }}
    - cwd: /opt/acme/{{ acme_acc }}/git

    {%- endif %}

acme_local_{{ loop.index }}:
  file.managed:
    - name: /opt/acme/{{ acme_acc }}/home/acme_local.sh
    - mode: 0700
    - contents: |
        #!/bin/bash
    {%- if "vars" in acme_params %}
      {%- for var_key, var_val in acme_params["vars"].items() %}
        export {{ var_key }}="{{ var_val }}"
      {%- endfor %}
    {%- endif %}
        /opt/acme/{{ acme_acc }}/home/acme.sh --home /opt/acme/{{ acme_acc }}/home --cert-home /opt/acme/{{ acme_acc }}/cert --config-home /opt/acme/{{ acme_acc }}/config {{ acme_params["args"]|default("") }} "$@"
acme_verify_and_issue_{{ loop.index }}:
  file.managed:
    - name: /opt/acme/{{ acme_acc }}/home/verify_and_issue.sh
    - mode: 0700
    - contents: |
        #!/bin/bash
        if [[ "$1" == "" ]]; then
          echo -e >&2 "ERROR: Use verify_and_issue.sh APP DOMAIN DOMAIN2 DOMAIN3...DOMAIN100"
          exit 1
        fi
        ACME_LOCAL_APP="$1"
        ACME_LOCAL_DOMAIN="$2"
        SAN=""
        if [[ "$#" > "2" ]]; then
          shift
          shift
          while [ -n "$1" ]; do
            SAN="${SAN}-d ${1} "
            shift
          done
        fi
        if openssl verify -CAfile /opt/acme/cert/${ACME_LOCAL_APP}_${ACME_LOCAL_DOMAIN}_ca.cer /opt/acme/cert/${ACME_LOCAL_APP}_${ACME_LOCAL_DOMAIN}_fullchain.cer 2>&1 | grep -q -i -e error -e cannot; then
          /opt/acme/{{ acme_acc }}/home/acme_local.sh \
            --cert-file /opt/acme/cert/${ACME_LOCAL_APP}_${ACME_LOCAL_DOMAIN}_cert.cer \
            --key-file /opt/acme/cert/${ACME_LOCAL_APP}_${ACME_LOCAL_DOMAIN}_key.key \
            --ca-file /opt/acme/cert/${ACME_LOCAL_APP}_${ACME_LOCAL_DOMAIN}_ca.cer \
            --fullchain-file /opt/acme/cert/${ACME_LOCAL_APP}_${ACME_LOCAL_DOMAIN}_fullchain.cer \
            --issue -d ${ACME_LOCAL_DOMAIN} $SAN
        else
          echo openssl verify OK
        fi


symlink for backwards compatibility {{ loop.index }}:
  file.symlink:
    - name: /opt/acme/home/{{ acme_acc }}/verify_and_issue.sh
    - target: /opt/acme/{{ acme_acc }}/home/verify_and_issue.sh
    - force: True

    {%- set a_loop = loop %}
    {%- for var_key, var_val in acme_params["vars"].items() %}
acme_acc_setenv_{{ a_loop.index }}_{{ loop.index }}:
  environ.setenv:
    - name: {{ var_key }}
    - value: "{{ var_val }}"
    - update_minion: True

    {%- endfor %}

    {%- if "chown" in acme_params %}
acme_chown_{{ loop.index }}:
  cmd.run:
    - name: chown -R {{ acme_params["chown"] }} /opt/acme

    {%- endif %}

Remove old ACME Cron for {{ acme_acc }}:
  cron.absent:
    - name: '"/opt/home/{{ acme_acc }}"/acme.sh --cron --home "/opt/acme/home/{{ acme_acc }}" --config-home "/opt/acme/config/{{ acme_acc }}" > /dev/null'
    - user: root

Create ACME Cron for {{ acme_acc }}:
  cron.present:
    - name: /opt/acme/{{ acme_acc }}/home/acme.sh --cron --home "/opt/acme/{{ acme_acc }}/home" --config-home "/opt/acme/{{ acme_acc }}/config" > /dev/null
    - identifier: ACME for {{ acme_acc }}
    - user: root
    - minute: {{ range(6, 54) | random }}
    - hour: 0

  {%- endfor %}
{% endif %}
