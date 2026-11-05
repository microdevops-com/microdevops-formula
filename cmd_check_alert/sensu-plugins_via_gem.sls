{% if pillar["cmd_check_alert"] is defined %}

  {%- set sensu_plugins_needed = [] %}

  {%- for check_group_name, check_group_params in pillar["cmd_check_alert"].items() %}
    {%- if "install_sensu-plugins" in check_group_params %}
      {%- for plugin in check_group_params["install_sensu-plugins"] %}
        {%- if plugin not in sensu_plugins_needed %}
          {%- do sensu_plugins_needed.append(plugin) %}
        {%- endif %}
      {%- endfor %}
    {%- endif %}
  {%- endfor %}

  {%- if sensu_plugins_needed|length > 0 %}
    {#- Ruby gem API dir per release: noble ships ruby 3.2, trixie ruby 3.3. KeyError on unknown release is intentional. #}
    {%- set ruby_gem_api = {"noble": "3.2.0", "trixie": "3.3.0"}[grains["oscodename"]] %}
sensu-plugins_ruby_dependencies_1:
  pkg.installed:
    - pkgs:
        - ruby-rubygems
        - ruby-dev

# Clean up legacy omnibus sensu-plugins-ruby (installed by sensu-plugins.sls before switching to gems)
sensu-plugins_legacy_pkg_purged:
  pkg.purged:
    - name: sensu-plugins-ruby

sensu-plugins_legacy_repo_absent:
  file.absent:
    - name: /etc/apt/sources.list.d/sensu_community.list

# Symlink /opt/sensu-plugins-ruby/embedded/bin -> /usr/local/bin for backwards compatibility
# force: legacy omnibus leaves embedded/bin as a real directory (files not owned by the package survive purge)
sensu-plugins_ruby_dependencies_2:
  file.symlink:
    - name: /opt/sensu-plugins-ruby/embedded/bin
    - target: /usr/local/bin
    - makedirs: True
    - force: True
    - require:
        - pkg: sensu-plugins_legacy_pkg_purged

    {%- for plugin in sensu_plugins_needed %}
sensu-plugins_install_{{ loop.index }}:
  cmd.run:
    - name: |
        if gem list | grep '^sensu-plugins-{{ plugin }} '; then
          echo sensu-plugins-{{ plugin }} gem is already installed
        else
          gem install sensu-plugins-{{ plugin }}
        fi
    - shell: /bin/bash

      {%- if plugin == "raid-checks" %}
sensu-plugins_install_{{ loop.index }}_patch_raid_1:
  file.managed:
    - name: /var/lib/gems/{{ ruby_gem_api }}/gems/sensu-plugins-raid-checks-3.0.0/bin/check-raid.rb
    - source: salt://cmd_check_alert/files/check-raid.rb
    - create: False
    - show_changes: True

      {%- endif %}

      {%- if plugin == "disk-checks" %}
sensu-plugins_install_{{ loop.index }}_patch_smart_1:
  file.managed:
    - name: /var/lib/gems/{{ ruby_gem_api }}/gems/sensu-plugins-disk-checks-5.1.4/bin/check-smart.rb
    - source: salt://cmd_check_alert/files/check-smart.rb
    - create: False
    - show_changes: True

      {%- endif %}

      {%- if plugin == "http" %}
sensu-plugins_install_{{ loop.index }}_patch_http_1:
  file.managed:
    - name: /var/lib/gems/{{ ruby_gem_api }}/gems/sensu-plugins-http-6.1.0/bin/check-http.rb
    - source: salt://cmd_check_alert/files/check-http.rb
    - create: False
    - show_changes: True

      {%- endif %}

    {%- endfor %}

  {%- endif %}

{% endif %}
