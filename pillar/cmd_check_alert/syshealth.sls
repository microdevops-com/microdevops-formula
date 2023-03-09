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
        hardware:
          cmd: :; ! dmesg -T | grep -i "hardware.*error" -m 10
          service: os
          resource: __hostname__:hardware
          severity_per_retcode:
            1: critical
        hardware-nvme:
          cmd: :; ! dmesg -T | grep -i "nvme.*err" -m 10
          service: os
          resource: __hostname__:hardware-nvme
          severity_per_retcode:
            1: critical
        hardware-cpu-temperature-throttling:
          cmd: :; ! dmesg -T | grep -i -e "temperature above threshold" -e "cpu clock throttled" -m 10
          service: os
          resource: __hostname__:hardware-cpu-temperature-throttling
          severity_per_retcode:
            1: critical
        oom:
          cmd: :; ! dmesg -T | grep -i -e "Out of memory" -e "oom"
          service: os
          resource: __hostname__:oom
          severity_per_retcode:
            1: critical
      {%- if grains.get("oscodename","") not in ["precise"] %}
        zombie:
          cmd: {{ ruby_prefix }}/check-process.rb -s Z -W 0 -C 0 -w 10 -c 15
          service: os
          resource: __hostname__:zombie
          severity_per_retcode:
            1: major
            2: critical
      {%- endif %}
