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

  # Sensu Plugins, if needed and the os is compatible
  {%- if sensu_plugins_needed|length > 0 and grains["oscodename"] not in ["precise"] %}

    {%- if grains["os_family"] == "Debian" %}
sensu-plugins_libc_dep:
  pkg.installed:
    - pkgs:
        - libc6-dev
        - python3-pip
        - python3-setuptools

sensu-plugins_mkdir_fix:
  cmd.run:
    - name: |
        ln -vs /bin/mkdir /usr/bin/mkdir
    - unless:
        - fun: file.file_exists
          path: /usr/bin/mkdir

    {%- endif %}

    {%- if grains["os_family"] == "Debian" and grains["oscodename"] not in ["buster", "bullseye", "jammy", "bookworm", "noble"] and grains["osarch"] not in ["arm64"] %}
sensu-plugins_repo:
  pkgrepo.managed:
    - humanname: Sensu Plugins
    - name: deb https://packagecloud.io/sensu/community/{{ grains["os"]|lower }}/ {{ grains["oscodename"] }} main
    - file: /etc/apt/sources.list.d/sensu_community.list
    - key_url: https://packagecloud.io/sensu/community/gpgkey
    - clean_file: True

    {%- elif grains["os_family"] == "Debian" and grains["oscodename"] in ["buster", "bullseye"] and grains["osarch"] not in ["arm64"] %}
sensu-plugins_repo:
  pkgrepo.managed:
    - humanname: Sensu Plugins
    - name: deb https://packagecloud.io/sensu/community/{{ grains["os"]|lower }}/ buster main
    - file: /etc/apt/sources.list.d/sensu_community.list
    - key_url: https://packagecloud.io/sensu/community/gpgkey
    - clean_file: True


    {%- elif grains["os_family"] == "Debian" and grains["oscodename"] in ["jammy", "bookworm", "noble", "plucky"] and grains["osarch"] not in ["arm64"] %}
sensu-plugins_repo:
  pkgrepo.managed:
    - humanname: Sensu Plugins
    - name: deb https://packagecloud.io/sensu/community/ubuntu/ focal main
    - file: /etc/apt/sources.list.d/sensu_community.list
    - key_url: https://packagecloud.io/sensu/community/gpgkey
    - clean_file: True

    {%- endif %}

    {%- if grains["os_family"] == "Debian" and grains["osarch"] not in ["arm64"] %}
sensu-plugins_pkg:
  pkg.latest:
    - refresh: True
    - pkgs:
        - sensu-plugins-ruby

    {%- endif %}

    {%- if grains["os_family"] == "Debian" and grains["osarch"] in ["arm64"] %}
sensu-plugins_rvm_keys:
  cmd.run:
    - name: |
        curl -sSL https://rvm.io/mpapis.asc | gpg --import -
        curl -sSL https://rvm.io/pkuczynski.asc | gpg --import -

sensu-plugins_rvm_install:
  cmd.run:
    - name: |
        curl -sSL https://get.rvm.io | bash -s stable
    - unless:
        - fun: file.directory_exists
          path: /usr/local/rvm

sensu-plugins_rvm_install_pkg_openssl:
  cmd.run:
    - name: |
        source /usr/local/rvm/scripts/rvm && rvm pkg install openssl
    - unless:
        - fun: file.file_exists
          path: /usr/local/rvm/usr/lib/libssl.so.1.0.0

sensu-plugins_rvm_install_ruby:
  cmd.run:
    - name: |
          source /usr/local/rvm/scripts/rvm && rvm install ruby-2.4.10 --with-openssl-dir=/usr/local/rvm/usr
          source /usr/local/rvm/scripts/rvm && rvm --default use ruby-2.4.10
    - unless:
        - fun: file.directory_exists
          path: /usr/local/rvm/rubies/ruby-2.4.10

# We need old version, as sensu-install is not compatible with newer versions and throws "invalid option: --no-ri" error
sensu-plugins_rvm_install_rubygems:
  cmd.run:
    - name: |
          source /usr/local/rvm/scripts/rvm && rvm install rubygems 2.6.14 --force
    - unless:
        - fun: file.directory_exists
          path: /usr/local/rvm/src/rubygems-2.6.14

sensu-plugins_rvm_gem_install_sensu-install:
  cmd.run:
    - name: |
          source /usr/local/rvm/scripts/rvm && /usr/local/rvm/rubies/ruby-2.4.10/bin/gem install sensu-install
    - unless:
        - fun: file.directory_exists
          path: /usr/local/rvm/gems/ruby-2.4.10/gems/sensu-install-0.1.0

    {%- endif %}

    {%- if grains["os_family"] == "RedHat" %}
sensu-plugins_repo:
  cmd.script:
    - name: script.rpm.sh
    - source: https://packagecloud.io/install/repositories/sensu/community/script.rpm.sh

    {%- endif %}

    {%- if grains["osarch"] in ["arm64"] %}
      {%- set ruby_bin_path = "/usr/local/rvm/rubies/ruby-2.4.10/bin" %}
      {%- set source_rvm = "source /usr/local/rvm/scripts/rvm" %}
    {%- else %}
      {%- set ruby_bin_path = "/opt/sensu-plugins-ruby/embedded/bin" %}
      {%- set source_rvm = "" %}
    {%- endif %}

# On plugins like sensu-plugins-http we have error "oj requires Ruby version >= 2.7."
# That error appeared when oj gem was updated to 3.14.0
# So we need to fix oj gem version to 3.13.9
sensu-plugins_fix_oj_gem:
  cmd.run:
    - name: |
        {{ source_rvm }}
        if {{ ruby_bin_path }}/gem list | grep '^oj ' | grep '3.13.9'; then
          echo oj 3.13.9 gem is already installed
        else
          {{ ruby_bin_path }}/gem install oj -v 3.13.9
        fi
    - shell: /bin/bash

# The same with ffi gem
sensu-plugins_fix_ffi_gem:
  cmd.run:
    - name: |
        {{ source_rvm }}
        if {{ ruby_bin_path }}/gem list | grep '^ffi ' | grep '1.15.5'; then
          echo ffi 1.15.5 gem is already installed
        else
          {{ ruby_bin_path }}/gem install ffi -v 1.15.5
        fi
    - shell: /bin/bash

# The same with domain_name gem
sensu-plugins_fix_domain_name_gem:
  cmd.run:
    - name: |
        {{ source_rvm }}
        if {{ ruby_bin_path }}/gem list | grep '^domain_name ' | grep '0.5.20190701'; then
          echo domain_name 0.5.20190701 gem is already installed
        else
          {{ ruby_bin_path }}/gem install domain_name -v 0.5.20190701
        fi
    - shell: /bin/bash

# The same with aws-eventstream gem
sensu-plugins_fix_aws-eventstream_gem:
  cmd.run:
    - name: |
        {{ source_rvm }}
        if {{ ruby_bin_path }}/gem list | grep '^aws-eventstream ' | grep '1.2.0'; then
          echo aws-eventstream 1.2.0 gem is already installed
        else
          {{ ruby_bin_path }}/gem install aws-eventstream -v 1.2.0
        fi
    - shell: /bin/bash

# The same with aws-sigv4 gem
sensu-plugins_fix_aws-sigv4_gem:
  cmd.run:
    - name: |
        {{ source_rvm }}
        if {{ ruby_bin_path }}/gem list | grep '^aws-sigv4 ' | grep '1.6.0'; then
          echo aws-sigv4 1.6.0 gem is already installed
        else
          {{ ruby_bin_path }}/gem install aws-sigv4 -v 1.6.0
        fi
    - shell: /bin/bash

# The same with mime-types
sensu-plugins_fix_mime-types_gem:
  cmd.run:
    - name: |
        {{ source_rvm }}
        if {{ ruby_bin_path }}/gem list | grep '^mime-types ' | grep '3.5.2'; then
          echo mime-types 3.3.1 gem is already installed
        else
          {{ ruby_bin_path }}/gem install mime-types -v 3.5.2
        fi
    - shell: /bin/bash

    {%- for plugin in sensu_plugins_needed %}
sensu-plugins_install_{{ loop.index }}:
  cmd.run:
    - name: {% if grains["osarch"] in ["arm64"] %}source /usr/local/rvm/scripts/rvm && /usr/local/rvm/gems/ruby-2.4.10/bin/{% endif %}sensu-install -p {{ plugin }}
    - shell: /bin/bash

      {%- if plugin == "raid-checks" %}
sensu-plugins_install_{{ loop.index }}_patch_raid_1:
  file.managed:
        {%- if grains["osarch"] not in ["arm64"] %}
    - name: /opt/sensu-plugins-ruby/embedded/lib/ruby/gems/2.4.0/gems/sensu-plugins-raid-checks-3.0.0/bin/check-raid.rb
        {%- else %}
    - name: /usr/local/rvm/gems/ruby-2.4.10/gems/sensu-plugins-raid-checks-3.0.0/bin/check-raid.rb
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
    - name: /usr/local/rvm/gems/ruby-2.4.10/gems/sensu-plugins-disk-checks-5.1.4/bin/check-smart.rb
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
    - name: /usr/local/rvm/gems/ruby-2.4.10/gems/sensu-plugins-http-6.1.0/bin/check-http.rb
        {%- endif %}
    - source: salt://cmd_check_alert/files/check-http.rb
    - create: False
    - show_changes: True

      {%- endif %}

    {%- endfor %}

    # On arm64 this is not needed as cacert is ok on rvm. Needed only for embedded.
    {%- if grains["osarch"] not in ["arm64"] %}
sensu-plugins_ssl_certs_dir:
  file.directory:
    - name: /opt/sensu-plugins-ruby/embedded/ssl/certs
    - user: root
    - group: root
    - mode: 0755
    - makedirs: True

sensu-plugins_update_cacert:
  file.managed:
    - name: /opt/sensu-plugins-ruby/embedded/ssl/certs/cacert.pem
    - source: salt://cmd_check_alert/files/cacert.pem

    {%- endif %}

  # Sensu Plugins, if needed and the os is compatible
  {%- endif %}

{% endif %}
