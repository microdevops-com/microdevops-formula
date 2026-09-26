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

  # app:docker:docker-ce_version - legacy wrongly named key
  # app:docker:version - correct key name
  # app:docker:daemon_json - optional, if not set, it will be set to '{"iptables": false}' by default
  {%- set docker_version = pillar["app"]["docker"].get("version", pillar["app"]["docker"].get("docker-ce_version")) %}
  {%- set docker_daemon_json = pillar["app"]["docker"].get("daemon_json", '{"iptables": false}') %}
  # if docker_version is defined and not empty, include docker-ce.sls with the specified version and daemon_json
  {%- if docker_version is defined and docker_version %}
    {%- set docker_ce = {"version": docker_version, "daemon_json": docker_daemon_json} %}
    {%- include "docker-ce/docker-ce.sls" with context %}
  {%- endif %}

  # Docker networks are created once and never replaced. docker_network.present (Salt 3006)
  # compares Docker 29's live Status counters as if they were config, so it "replaced" the
  # network - cutting every container off it - on each apply. An existing network whose
  # subnet/gateway differ from pillar now fails here ("already exists") instead of being
  # silently replaced; recreating a live network is a decision, not a side effect.
  {%- if "networks" in pillar["app"]["docker"] %}
    {%- if pillar["app"]["docker"]["networks"] is mapping %}

      {%- for net_name, net_params in pillar["app"]["docker"]["networks"].items() %}
        {%- if not "deploy_only" in pillar["app"]["docker"] or net_name == pillar["app"]["docker"]["deploy_only"] %}
docker_network_{{ loop.index }}:
  cmd.run:
    - name: docker network create --subnet {{ net_params["subnet"] }} --gateway {{ net_params["gateway"] }} {{ net_name }}
    - unless: test "$(docker network inspect {{ net_name }} --format '{% raw %}{{range .IPAM.Config}}{{.Subnet}} {{.Gateway}}{{end}}{% endraw %}' 2>/dev/null)" = "{{ net_params["subnet"] }} {{ net_params["gateway"] }}"

        {%- endif %}
      {%- endfor %}

    {%- else %}

      {%- for net in pillar["app"]["docker"]["networks"] %}
docker_network_{{ loop.index }}:
  cmd.run:
    - name: docker network create --subnet {{ net["subnet"] }} --gateway {{ net["gateway"] }} {{ net["name"] }}
    - unless: test "$(docker network inspect {{ net["name"] }} --format '{% raw %}{{range .IPAM.Config}}{{.Subnet}} {{.Gateway}}{{end}}{% endraw %}' 2>/dev/null)" = "{{ net["subnet"] }} {{ net["gateway"] }}"

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
    # Credentials go in through the environment and stdin, not the command line: the command
    # line is printed as the state's Name in every state run output.
    - name: printf '%s' "$DOCKER_REGISTRY_PASSWORD" | docker login -u "$DOCKER_REGISTRY_USERNAME" --password-stdin "{{ app["docker_registry_login"]["registry"] }}"
    - env:
      - DOCKER_REGISTRY_USERNAME: {{ app["docker_registry_login"]["username"] | string | yaml_encode }}
      - DOCKER_REGISTRY_PASSWORD: {{ app["docker_registry_login"]["password"] | string | yaml_encode }}
      {%- endif %}

docker_app_docker_pull_{{ loop.index }}:
  cmd.run:
    - name: docker pull {{ app["image"] }}

      {%- if "pre_start" in app %}
docker_app_pre_start_pull_{{ loop.index }}:
  cmd.run:
    - name: docker pull {{ app["pre_start"]["image"] }}

# One-shot container run before the app container is created or updated (e.g. database
# migrations), with the app's environment, networks, binds and user but no published ports.
# It is removed after it exits; a non-zero exit fails this state, and the app container
# below requires it, so the app is then left untouched.
docker_app_pre_start_{{ loop.index }}:
  docker_container.run:
    - name: app-{{ app_name }}-pre-start
    - image: {{ app["pre_start"]["image"] }}
    - user: {{ app.get("user", "root") }}
    # json, not the Python repr: YAML misreads Python quoting (a backslash comes out doubled)
    - environment: {{ app["environment"] | default([]) | json }}
    - binds: {{ app["binds"] | default([]) | replace("__APP_NAME__", app_name) }}
        {%- if "networks" in app %}
    - networks: {{ app["networks"] | replace("__APP_NAME__", app_name) }}
        {%- endif %}
        {%- if "command" in app["pre_start"] %}
    - command: {{ app["pre_start"]["command"] }}
        {%- endif %}
    - auto_remove: True
    - replace: True
    - require:
      - cmd: docker_app_pre_start_pull_{{ loop.index }}

      {%- endif %}
docker_app_container_{{ loop.index }}:
  docker_container.running:
    - name: app-{{ app_name }}
    - user: {{ app.get("user", "root") }}
    - image: {{ app["image"] }}
    - detach: True
    - restart_policy: unless-stopped
    - publish: {{ app["publish"] | default([]) }}
    # json, not the Python repr: YAML misreads Python quoting (a backslash comes out doubled)
    - environment: {{ app["environment"] | default([]) | json }}
    - binds: {{ app["binds"] | default([]) | replace("__APP_NAME__", app_name) }}
      {%- if "networks" in app %}
    - networks: {{ app["networks"] | replace("__APP_NAME__", app_name) }}
      {%- endif %}
    - privileged: {{ app["privileged"] | default(False) }}
      {%- if "pre_start" in app %}
    - require:
      - docker_container: docker_app_pre_start_{{ loop.index }}
      {%- endif %}
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
