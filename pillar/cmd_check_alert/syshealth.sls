{%- set ruby_prefix = "/opt/sensu-plugins-ruby/embedded/bin" %}
{%- if grains["osarch"] in ["arm64"] %}
  {%- set ruby_prefix = "source /usr/local/rvm/scripts/rvm && /usr/local/rvm/gems/ruby-2.4.0/bin" %}
{%- endif %}
cmd_check_alert:
  syshealth:
    cron: '*/10'
    install_sensu-plugins:
      - process-checks
    config:
      enabled: True
      limits:
        time: 900
        threads: 5
      defaults:
        timeout: 15
        severity: critical
      checks:
        dmesg-has-hardware-errors:
          cmd: ! dmesg -T | grep -i "hardware.*error" -m 10
          service: os
          resource: __hostname__:hardware
          severity_per_retcode:
            1: critical
        dmesg-has-nvme-errors:
          cmd: ! dmesg -T | grep -i "nvme.*err" -m 10
          service: os
          resource: __hostname__:hardware
          severity_per_retcode:
            1: critical
        has-oom-kills:
          cmd: :; ! dmesg -T | grep "Out of memory"
          service: os
          resource: __hostname__:oom
          severity_per_retcode:
            1: critical
      {%- if grains.get("oscodename","") not in ["precise"] %}
        has-zombies:
          cmd: {{ ruby_prefix }}/check-process.rb -s Z -W 0 -C 0 -w 10 -c 15
          service: os
          resource: __hostname__:zombie
          severity_per_retcode:
            1: major
            2: critical
      {%- endif %}
