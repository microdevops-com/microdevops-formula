{% if pillar["docker-ce"] is defined and "compose" in pillar["docker-ce"] %}
docker-ce_compose_run_1:
  cmd.run:
    - name: |
        set -e
  {%- if pillar["docker-ce"]["compose"] == "latest" %}
        curl -L https://github.com/docker/compose/releases/latest/download/docker-compose-`uname -s`-`uname -m` -o /usr/local/bin/docker-compose
  {%- else %}
        curl -L https://github.com/docker/compose/releases/download/{{ pillar["docker-ce"]["compose"] }}/docker-compose-`uname -s`-`uname -m` -o /usr/local/bin/docker-compose
  {%- endif %}
        chmod +x /usr/local/bin/docker-compose

{% endif %}
