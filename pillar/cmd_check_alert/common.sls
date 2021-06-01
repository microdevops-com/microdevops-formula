cmd_check_alert:
  cpu:
    cron: '*/3'
    install_sensu-plugins:
      - cpu-checks
    config:
      enabled: True
      limits:
        time: 60
        threads: 5
      defaults:
        timeout: 60
        severity: critical
      checks:
        cpu-usage:
          disabled: True
          cmd: /opt/sensu-plugins-ruby/embedded/bin/check-cpu.rb -w 90 -c 95
          severity_per_retcode:
            1: major
            2: critical
          service: cpu
          resource: __hostname__:cpu-usage
  memory:
    cron: '*/3'
    install_sensu-plugins:
      - memory-checks
    config:
      enabled: True
      limits:
        time: 60
        threads: 5
      defaults:
        timeout: 60
        severity: critical
      checks:
        memory-percent:
          cmd: /opt/sensu-plugins-ruby/embedded/bin/check-memory-percent.rb -w 80 -c 90
          severity_per_retcode:
            1: major
            2: critical
          service: memory
          resource: __hostname__:memory-percent
        swap-percent:
          cmd: /opt/sensu-plugins-ruby/embedded/bin/check-swap-percent.rb -w 70 -c 80
          severity_per_retcode:
            1: major
            2: critical
          service: memory
          resource: __hostname__:swap-percent
        swap-usage:
          cmd: /opt/sensu-plugins-ruby/embedded/bin/check-swap.rb -w 1024 -c 2048
          severity_per_retcode:
            1: major
            2: critical
          service: memory
          resource: __hostname__:swap-usage
  network:
    cron: '*/15'
    install_sensu-plugins:
      - network-checks
    config:
      enabled: True
      limits:
        time: 60
        threads: 5
      defaults:
        timeout: 60
        severity: critical
      checks:
        netfilter-conntrack:
          cmd: /opt/sensu-plugins-ruby/embedded/bin/check-netfilter-conntrack.rb -w 80 -c 90
          severity_per_retcode:
            1: major
            2: critical
          service: network
          resource: __hostname__:netfilter-conntrack
        iptables_input_drop:
          cmd: iptables -w 60 -S | grep -q -e "-P INPUT DROP"
          severity: security
          service: network
          resource: __hostname__:iptables_input_drop
        iptables_open_from_any:
          # we heck rules that are without source, exclude standard ufw rules, exclude open 80, 443, 2226
          cmd: IPT_RULES=$(iptables -w 60 -S | grep -e "-j ACCEPT" | grep -v -e "-s " | grep -v -e ufw-before-forward -e ufw-before-input -e ufw-before-output -e ufw-skip-to-policy-forward -e ufw-skip-to-policy-output -e ufw-track-forward -e ufw-track-output -e ufw-user-limit-accept | grep -v -e "--dport 80" -e "--dport 443" -e "--dport 2226"); if [[ -n "$IPT_RULES" ]]; then echo "${IPT_RULES}"; ( exit 1 ); fi
          severity: security
          service: network
          resource: __hostname__:iptables_open_from_any
  disk:
    cron:
      minute: '10'
      hour: '*/6'
    install_sensu-plugins:
      - disk-checks
      - raid-checks
    config:
      enabled: True
      limits:
        time: 60
        threads: 5
      defaults:
        timeout: 60
        severity: critical
      checks:
        fstab-mounts:
          cmd: /opt/sensu-plugins-ruby/embedded/bin/check-fstab-mounts.rb
          severity_per_retcode:
            1: minor
            2: major
          service: disk
          resource: __hostname__:fstab-mounts
        smart:
{% if grains["virtual"] != "physical" %}
          disabled: True
{% endif %}
          cmd: /opt/sensu-plugins-ruby/embedded/bin/check-smart.rb
          severity_per_retcode:
            1: major
            2: critical
          service: disk
          resource: __hostname__:smart
        raid:
{% if grains["virtual"] != "physical" %}
          disabled: True
{% endif %}
          cmd: /opt/sensu-plugins-ruby/embedded/bin/check-raid.rb
          severity_per_retcode:
            1: major
            2: critical
          service: disk
          resource: __hostname__:raid
  pkg:
    cron:
      minute: '15'
      hour: '10'
{% if grains["oscodename"] in ["bionic", "focal"] %}
    install_cvescan: True
{% endif %}
    config:
      enabled: True
      limits:
        time: 60
        threads: 5
      defaults:
        timeout: 60
        severity: minor
      checks:
        cvescan:
{% if grains["oscodename"] not in ["bionic", "focal"] %}
          disabled: True
{% endif %}
          cmd: cvescan -p all
          severity_per_retcode:
            1: minor
            2: minor
            3: security
            4: security
          service: pkg
          resource: __hostname__:cvescan
        yum_security:
{% if grains["os_family"] != "RedHat" %}
          disabled: True
{% endif %}
          cmd: yum -q makecache && if yum --cacheonly updateinfo summary updates | grep -q "Security"; then yum --cacheonly updateinfo list updates | grep "/Sec."; yum --cacheonly updateinfo summary updates | grep "Security"; ( exit 2 ); else true; fi
          severity_per_retcode:
            1: minor
            2: security
          service: pkg
          resource: __hostname__:yum_security
