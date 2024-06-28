{% if pillar["cmd_check_alert"] is defined %}

  {%- set sensu_plugins_needed = [] %}

cmd_check_alert_dir:
  file.directory:
    - name: /opt/sysadmws/cmd_check_alert/checks
    - user: root
    - group: root
    - mode: 0775
    - makedirs: True

# Remove common config and cron, we've switched to separate config and cron per check pillar
cmd_check_alert_commong_config_absent:
  file.absent:
    - name: /opt/sysadmws/cmd_check_alert/cmd_check_alert.yaml

cmd_check_alert_common_cron_absent:
  cron.absent:
    - identifier: cmd_check_alert
    - name: /opt/sysadmws/cmd_check_alert/cmd_check_alert.py
    - user: root

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
sensu-plugins_ssl_certs_dir:
  file.directory:
    - name: /opt/sensu-plugins-ruby/embedded/ssl/certs
    - user: root
    - group: root
    - mode: 0755
    - makedirs: True

    {%- if grains["os_family"] == "Debian" %}
      # Sensu Plugins embedded doesn't work on arm64, but can be installed manually, see below
      {%- if grains["oscodename"] not in ["precise", "buster", "bullseye", "jammy", "bookworm"] and grains["osarch"] not in ["arm64"] %}
sensu-plugins_repo:
  pkgrepo.managed:
    - humanname: Sensu Plugins
    - name: deb https://packagecloud.io/sensu/community/{{ grains["os"]|lower }}/ {{ grains["oscodename"] }} main
    - file: /etc/apt/sources.list.d/sensu_community.list
    - key_url: https://packagecloud.io/sensu/community/gpgkey
    - clean_file: True
      {%- elif grains["oscodename"] in ["buster", "bullseye"] %}
sensu-plugins_repo:
  pkgrepo.managed:
    - humanname: Sensu Plugins
    - name: deb https://packagecloud.io/sensu/community/{{ grains["os"]|lower }}/ buster main
    - file: /etc/apt/sources.list.d/sensu_community.list
    - key_url: https://packagecloud.io/sensu/community/gpgkey
    - clean_file: True
      {%- elif grains["oscodename"] in ["jammy", "bookworm"] %}
sensu-plugins_repo:
  pkgrepo.managed:
    - humanname: Sensu Plugins
    - name: deb https://packagecloud.io/sensu/community/ubuntu/ focal main
    - file: /etc/apt/sources.list.d/sensu_community.list
    - key_url: https://packagecloud.io/sensu/community/gpgkey
    - clean_file: True
      {%- endif %}

      {%- if grains["oscodename"] not in ["precise"] %}
sensu-plugins_libc_dep:
  pkg.installed:
    - pkgs:
        - libc6-dev
        - python3-pip
        - python3-setuptools
      {%- endif %}

sensu-plugins_mkdir_fix:
  cmd.run:
    - name: |
        bash -c 'if [[ ! -e /usr/bin/mkdir ]]; then ln -vs /bin/mkdir /usr/bin/mkdir; else echo /usr/bin/mkdir exists; fi'

    {%- elif grains["os_family"] == "RedHat" %}
sensu-plugins_repo:
  cmd.script:
    - name: script.rpm.sh
    - source: https://packagecloud.io/install/repositories/sensu/community/script.rpm.sh

    {%- endif %}

    {%- if grains["oscodename"] not in ["precise"] %}
      # On arm64 install is not automated yet, install manually:
      # command curl -sSL https://rvm.io/mpapis.asc | gpg --import -
      # command curl -sSL https://rvm.io/pkuczynski.asc | gpg --import -
      # curl -sSL https://get.rvm.io | bash -s stable
      # source /usr/local/rvm/scripts/rvm 
      # rvm install ruby-2.4.0
      # rvm --default use ruby-2.4.0
      # rvm install rubygems 2.6.14 --force
      # gem install sensu-install
      {%- if grains["osarch"] not in ["arm64"] %}
sensu-plugins_pkg:
  pkg.latest:
    - refresh: True
    - pkgs:
        - sensu-plugins-ruby

      {%- endif %}

# On plugins like sensu-plugins-http we have error "oj requires Ruby version >= 2.7."
# That error appeared when oj gem was updated to 3.14.0
# So we need to fix oj gem version to 3.13.9
sensu-plugins_fix_oj_gem:
  cmd.run:
      {% if grains["osarch"] in ["arm64"] %}
    - name: |
        source /usr/local/rvm/scripts/rvm
        if /usr/local/rvm/gems/ruby-2.4.0/wrappers/gem list | grep '^oj ' | grep '3.13.9'; then
          echo oj 3.13.9 gem is already installed
        else
          /usr/local/rvm/gems/ruby-2.4.0/wrappers/gem install oj -v 3.13.9
        fi
      {% else %}
    - name: |
        if /opt/sensu-plugins-ruby/embedded/bin/gem list | grep '^oj ' | grep '3.13.9'; then
          echo oj 3.13.9 gem is already installed
        else
          /opt/sensu-plugins-ruby/embedded/bin/gem install oj -v 3.13.9
        fi
      {% endif %}
    - shell: /bin/bash

# The same with ffi gem
sensu-plugins_fix_ffi_gem:
  cmd.run:
      {% if grains["osarch"] in ["arm64"] %}
    - name: |
        source /usr/local/rvm/scripts/rvm
        if /usr/local/rvm/gems/ruby-2.4.0/wrappers/gem list | grep '^ffi ' | grep '1.15.5'; then
          echo ffi 1.15.5 gem is already installed
        else
          /usr/local/rvm/gems/ruby-2.4.0/wrappers/gem install ffi -v 1.15.5
        fi
      {% else %}
    - name: |
        if /opt/sensu-plugins-ruby/embedded/bin/gem list | grep '^ffi ' | grep '1.15.5'; then
          echo ffi 1.15.5 gem is already installed
        else
          /opt/sensu-plugins-ruby/embedded/bin/gem install ffi -v 1.15.5
        fi
      {% endif %}
    - shell: /bin/bash

# The same with domain_name gem
sensu-plugins_fix_domain_name_gem:
  cmd.run:
      {% if grains["osarch"] in ["arm64"] %}
    - name: |
        source /usr/local/rvm/scripts/rvm
        if /usr/local/rvm/gems/ruby-2.4.0/wrappers/gem list | grep '^domain_name ' | grep '0.5.20190701'; then
          echo domain_name 0.5.20190701 gem is already installed
        else
          /usr/local/rvm/gems/ruby-2.4.0/wrappers/gem install domain_name -v 0.5.20190701
        fi
      {% else %}
    - name: |
        if /opt/sensu-plugins-ruby/embedded/bin/gem list | grep '^domain_name ' | grep '0.5.20190701'; then
          echo domain_name 0.5.20190701 gem is already installed
        else
          /opt/sensu-plugins-ruby/embedded/bin/gem install domain_name -v 0.5.20190701
        fi
      {% endif %}
    - shell: /bin/bash

# The same with aws-eventstream gem
sensu-plugins_fix_aws-eventstream_gem:
  cmd.run:
      {% if grains["osarch"] in ["arm64"] %}
    - name: |
        source /usr/local/rvm/scripts/rvm
        if /usr/local/rvm/gems/ruby-2.4.0/wrappers/gem list | grep '^aws-eventstream ' | grep '1.2.0'; then
          echo aws-eventstream 1.2.0 gem is already installed
        else
          /usr/local/rvm/gems/ruby-2.4.0/wrappers/gem install aws-eventstream -v 1.2.0
        fi
      {% else %}
    - name: |
        if /opt/sensu-plugins-ruby/embedded/bin/gem list | grep '^aws-eventstream ' | grep '1.2.0'; then
          echo aws-eventstream 1.2.0 gem is already installed
        else
          /opt/sensu-plugins-ruby/embedded/bin/gem install aws-eventstream -v 1.2.0
        fi
      {% endif %}
    - shell: /bin/bash

# The same with aws-sigv4 gem
sensu-plugins_fix_aws-sigv4_gem:
  cmd.run:
      {% if grains["osarch"] in ["arm64"] %}
    - name: |
        source /usr/local/rvm/scripts/rvm
        if /usr/local/rvm/gems/ruby-2.4.0/wrappers/gem list | grep '^aws-sigv4 ' | grep '1.6.0'; then
          echo aws-sigv4 1.6.0 gem is already installed
        else
          /usr/local/rvm/gems/ruby-2.4.0/wrappers/gem install aws-sigv4 -v 1.6.0
        fi
      {% else %}
    - name: |
        if /opt/sensu-plugins-ruby/embedded/bin/gem list | grep '^aws-sigv4 ' | grep '1.6.0'; then
          echo aws-sigv4 1.6.0 gem is already installed
        else
          /opt/sensu-plugins-ruby/embedded/bin/gem install aws-sigv4 -v 1.6.0
        fi
      {% endif %}
    - shell: /bin/bash

      {%- for plugin in sensu_plugins_needed %}
sensu-plugins_install_{{ loop.index }}:
  cmd.run:
    - name: {% if grains["osarch"] in ["arm64"] %}source /usr/local/rvm/scripts/rvm && /usr/local/rvm/gems/ruby-2.4.0/bin/{% endif %}sensu-install -p {{ plugin }}
    - shell: /bin/bash

        {%- if plugin == "raid-checks" %}
sensu-plugins_install_{{ loop.index }}_patch_raid_1:
  file.managed:
          {%- if grains["osarch"] not in ["arm64"] %}
    - name: /opt/sensu-plugins-ruby/embedded/lib/ruby/gems/2.4.0/gems/sensu-plugins-raid-checks-3.0.0/bin/check-raid.rb
          {%- else %}
    - name: /usr/local/rvm/gems/ruby-2.4.0/gems/sensu-plugins-raid-checks-3.0.0/bin/check-raid.rb
          {%- endif %}
    - source: salt://cmd_check_alert/files/check-raid.rb
    - create: False
    - show_changes: True

        {%- endif %}
        {%- if plugin == "disk-checks" %}
sensu-plugins_install_{{ loop.index }}_patch_smart_1:
  file.managed:
          {%- if grains["osarch"] not in ["arm64"] %}
    - name: /opt/sensu-plugins-ruby/embedded/lib/ruby/gems/2.4.0/gems/sensu-plugins-disk-checks-5.1.4/bin/check-smart.rb
          {%- else %}
    - name: /usr/local/rvm/gems/ruby-2.4.0/gems/sensu-plugins-disk-checks-5.1.4/bin/check-smart.rb
          {%- endif %}
    - source: salt://cmd_check_alert/files/check-smart.rb
    - create: False
    - show_changes: True

        {%- endif %}
        {%- if plugin == "http" %}
sensu-plugins_install_{{ loop.index }}_patch_http_1:
  file.managed:
          {%- if grains["osarch"] not in ["arm64"] %}
    - name: /opt/sensu-plugins-ruby/embedded/lib/ruby/gems/2.4.0/gems/sensu-plugins-http-6.1.0/bin/check-http.rb
          {%- else %}
    - name: /usr/local/rvm/gems/ruby-2.4.0/gems/sensu-plugins-http-6.1.0/bin/check-http.rb
          {%- endif %}
    - source: salt://cmd_check_alert/files/check-http.rb
    - create: False
    - show_changes: True

        {%- endif %}
      {%- endfor %}
    {%- endif %}

    {%- if grains["osarch"] not in ["arm64"] %}
      # On arm64 this is not needed as cacert is ok on rvm. Needed only for embedded.
sensu-plugins_update_cacert:
  file.managed:
    - name: /opt/sensu-plugins-ruby/embedded/ssl/certs/cacert.pem
    - source: salt://cmd_check_alert/files/cacert.pem
    {%- endif %}

  {%- endif %}

  {%- for check_group_name, check_group_params in pillar["cmd_check_alert"].items() if check_group_name not in ["hostname_override"] %}
    {%- if "hostname_override" in pillar["cmd_check_alert"] %}
      {%- do check_group_params["config"].update({"hostname_override": pillar["cmd_check_alert"]["hostname_override"]}) %}
    {%- endif %}
    # There is some bug in serializer that causes int config keys to serialize as strings under salt-ssh and as ints under salt, which leads to flapping of config file
    # Fix by forcing severity_per_retcode to string
    # defaults
    {%- if "defaults" in check_group_params["config"] and "severity_per_retcode" in check_group_params["config"]["defaults"] %}
      {%- set new_severity_per_retcode = {} %}
      {%- for retcode, severity in check_group_params["config"]["defaults"]["severity_per_retcode"].items() %}
        {%- do new_severity_per_retcode.update({retcode|string: severity}) %}
      {%- endfor %}
      {%- do check_group_params["config"]["defaults"].update({"severity_per_retcode": {}}) %}
      {%- do check_group_params["config"]["defaults"]["severity_per_retcode"].update(new_severity_per_retcode) %}
    {%- endif %}
    # checks
    {%- if "checks" in check_group_params["config"] %}
      {%- for check_name, check_params in check_group_params["config"]["checks"].items() %}
        {%- if "severity_per_retcode" in check_params %}
          {%- set new_severity_per_retcode = {} %}
          {%- for retcode, severity in check_params["severity_per_retcode"].items() %}
            {%- do new_severity_per_retcode.update({retcode|string: severity}) %}
          {%- endfor %}
          {%- do check_group_params["config"]["checks"][check_name].update({"severity_per_retcode": {}}) %}
          {%- do check_group_params["config"]["checks"][check_name]["severity_per_retcode"].update(new_severity_per_retcode) %}
        {%- endif %}
        # Also apply cmd_override over cmd here
        {%- if "cmd_override" in check_params %}
          {%- do check_group_params["config"]["checks"][check_name].update({"cmd": check_params["cmd_override"]}) %}
        {%- endif %}
      {%- endfor %}
    {%- endif %}
cmd_check_alert_config_managed_{{ loop.index }}:
  file.serialize:
    - name: /opt/sysadmws/cmd_check_alert/checks/{{ check_group_name }}.yaml
    - mode: 0600
    - user: root
    - group: root
    - show_changes: True
    - create: True
    - merge_if_exists: False
    - formatter: yaml
    - serializer_opts:
      - width: 1024 # otherwise it will split long commands in multiple lines
    - dataset: {{ check_group_params["config"] }}

cmd_check_alert_cron_managed_{{ loop.index }}:
  cron.present:
    - identifier: cmd_check_alert_{{ check_group_name }}
    - name: /opt/sysadmws/cmd_check_alert/cmd_check_alert.py --yaml checks/{{ check_group_name }}.yaml
    - user: root
    {%- if "minute" in check_group_params["cron"] or "hour" in check_group_params["cron"] or "daymonth" in check_group_params["cron"] or "month" in check_group_params["cron"] or "dayweek" in check_group_params["cron"] %}
      {%- if "minute" in check_group_params["cron"] %}
    - minute: "{{ check_group_params["cron"]["minute"] }}"
      {%- endif %}
      {%- if "hour" in check_group_params["cron"] %}
    - hour: "{{ check_group_params["cron"]["hour"] }}"
      {%- endif %}
      {%- if "daymonth" in check_group_params["cron"] %}
    - daymonth: "{{ check_group_params["cron"]["daymonth"] }}"
      {%- endif %}
      {%- if "month" in check_group_params["cron"] %}
    - month: "{{ check_group_params["cron"]["month"] }}"
      {%- endif %}
      {%- if "dayweek" in check_group_params["cron"] %}
    - dayweek: "{{ check_group_params["cron"]["dayweek"] }}"
      {%- endif %}
    {%- else %}
    - minute: "{{ check_group_params["cron"] }}"
    {%- endif %}

    {%- if "files" in check_group_params %}
      {%- set a_loop = loop %}
      {%- for file_name, file_data_items in check_group_params["files"].items() %}
        {%- set contents_list = [] %}
        {%- for file_data_item_name, file_data_item_data in file_data_items.items()|sort %}
          {%- do contents_list.append(file_data_item_data) %}
        {%- endfor %}
cmd_check_alert_file_managed_{{ loop.index }}_{{ a_loop.index }}:
  file.managed:
    - name: {{ file_name }}
    - contents: {{ contents_list | json }}

      {%- endfor %}
    {%- endif %}

  {%- endfor %}

{% else %}
cmd_check_alert_nothing_done_info:
  test.configurable_test_state:
    - name: nothing_done
    - changes: False
    - result: True
    - comment: |
        INFO: This state was not configured for a minion of this type, so nothing has been done. But it is OK.

{% endif %}
