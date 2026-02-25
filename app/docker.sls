{% if pillar["_errors"] is defined %}
docker_pillar_render_errors:
  test.configurable_test_state:
    - name: nothing_done
    - changes: False
    - result: False
    - comment: |
        ERROR: There are pillar errors, so nothing has been done.
        {{ pillar["_errors"] | json() }}

{% elif pillar["app"] is defined and "docker" in pillar["app"] and "apps" in pillar["app"]["docker"] %}

  {%- set app_type = "docker" %} # required for _pkg.sls

  {%- include "app/_pkg.sls" with context %}
  {%- include "app/_pre_deploy.sls" with context %}

  {%- if pillar["app"]["docker"]["docker-ce_version"] is defined %}
    {%- set docker_ce = {"version": pillar["app"]["docker"]["docker-ce_version"],
                         "daemon_json": '{"iptables": false}'} %}
    {%- include "docker-ce/docker-ce.sls" with context %}
  {%- endif %}

  {%- if "networks" in pillar["app"]["docker"] %}
    {%- if pillar["app"]["docker"]["networks"] is mapping %}

      {%- for net_name, net_params in pillar["app"]["docker"]["networks"].items() %}
        {%- if not "deploy_only" in pillar["app"]["docker"] or net_name == pillar["app"]["docker"]["deploy_only"] %}
docker_network_{{ loop.index }}:
  docker_network.present:
    - name: {{ net_name }}
    - subnet: {{ net_params["subnet"] }}
    - gateway: {{ net_params["gateway"] }}

        {%- endif %}
      {%- endfor %}

    {%- else %}

      {%- for net in pillar["app"]["docker"]["networks"] %}
docker_network_{{ loop.index }}:
  docker_network.present:
    - name: {{ net["name"] }}
    - subnet: {{ net["subnet"] }}
    - gateway: {{ net["gateway"] }}

      {%- endfor %}

    {%- endif %}
  {%- endif %}

  {%- for app_name, app in pillar["app"]["docker"]["apps"].items() %}
    {%- if not "deploy_only" in pillar["app"]["docker"] or app_name == pillar["app"]["docker"]["deploy_only"] %}

docker_app_dir_{{ loop.index }}:
  file.directory:
    - name: {{ app["home"]|replace("__APP_NAME__", app_name) }}
    - mode: 755
    - makedirs: True

      {%- set files = app.get("files", {}) %}
      {%- if files is none %}
        {%- set files = {} %}
      {%- endif %}
      {%- set file_manager_defaults = {"default_user": "root", "default_group": "root",
                                       "replace_old": "__APP_NAME__", "replace_new": app_name} %}
      {%- include "_include/file_manager/init.sls" with context %}

      {%- if app["docker_registry_login"] is defined %}
docker_app_docker_login_{{ loop.index }}:
  cmd.run:
    - name: docker login -u "{{ app["docker_registry_login"]["username"] }}" -p "{{ app["docker_registry_login"]["password"] }}" "{{ app["docker_registry_login"]["registry"] }}"
      {%- endif %}

docker_app_docker_pull_{{ loop.index }}:
  cmd.run:
    - name: docker pull {{ app["image"] }}

docker_app_container_{{ loop.index }}:
  docker_container.running:
    - name: app-{{ app_name }}
    - user: {{ app.get("user", "root") }}
    - image: {{ app["image"] }}
    - detach: True
    - restart_policy: unless-stopped
    - publish: {{ app["publish"] | default([]) }}
    - environment: {{ app["environment"] | default([]) }}
    - binds: {{ app["binds"] | default([]) | replace("__APP_NAME__", app_name) }}
      {%- if "networks" in app %}
    - networks: {{ app["networks"] | replace("__APP_NAME__", app_name) }}
      {%- endif %}
    - privileged: {{ app["privileged"] | default(False) }}
      {%- if app["retries_docker_running"] is defined %}
    - retry:
        attempts: {{ app["retries_docker_running"] }}
        interval: {{ app.get("retries_interval_docker_running", 5) }}
        until: True
      {%- endif %}
      {%- if "command" in app %}
    - command : {{ app["command"] }}
      {%- endif %}
      {%- if "volumes" in app %}
    - volumes:
        {%- for volume in app["volumes"] %}
      - {{ volume | replace("__APP_NAME__", app_name) }}
        {%- endfor %}
      {%- endif %}
      {%- if "volumes_from" in app %}
    - volumes_from: {{ app["volumes_from"] }}
      {%- endif %}
      
      {%- if app["exec_after_deploy"] is defined %}
docker_app_container_exec_{{ loop.index }}:
  cmd.run:
    - name: docker exec app-{{ app_name }} {{ app["exec_after_deploy"] }}
      {%- endif %}

      {%- if app["cron"] is defined %}
        {%- set i_loop = loop %}
        {%- for cron in app["cron"] %}
docker_app_container_cron_{{ i_loop.index }}_{{ loop.index }}:
  cron.present:
    - name: docker exec app-{{ app_name }} {{ cron["cmd"] }}
    - identifier: docker-app-{{ app_name }}-{{ loop.index }}
    - user: root
          {%- if cron["minute"] is defined %}
    - minute: "{{ cron["minute"] }}"
          {%- endif %}
          {%- if cron["hour"] is defined %}
    - hour: "{{ cron["hour"] }}"
          {%- endif %}
          {%- if cron["daymonth"] is defined %}
    - daymonth: "{{ cron["daymonth"] }}"
          {%- endif %}
          {%- if cron["month"] is defined %}
    - month: "{{ cron["month"] }}"
          {%- endif %}
          {%- if cron["dayweek"] is defined %}
    - dayweek: "{{ cron["dayweek"] }}"
          {%- endif %}
          {%- if cron["special"] is defined %}
    - special: "{{ cron["special"] }}"
          {%- endif %}
        {%- endfor %}
      {%- endif %}
    {%- endif %}
  {%- endfor %}

  {%- include "app/_post_deploy.sls" with context %}

{% endif %}
