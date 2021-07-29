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
        severity: major
      checks:
        cpu-usage:
          disabled: True
          cmd: /opt/sensu-plugins-ruby/embedded/bin/check-cpu.rb -w 90 -c 95
          severity_per_retcode:
            1: minor
            2: major
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
        severity: major
      checks:
        memory-percent:
{% if grains["virtual"] == "lxc"|lower or grains["oscodename"] in ["precise"] %}
          # Available memory in LXC containers is shown wrong (without buffers/cache).
          # Only host machine will have mem checks enabled - it is usually ok.
          # But if you have LXC container with memory limits by LXC - you should enable mem checks for it individually.
          disabled: True
{% endif %}
          cmd: /opt/sensu-plugins-ruby/embedded/bin/check-memory-percent.rb -w 91 -c 95
          severity_per_retcode:
            1: minor
            2: major
          service: memory
          resource: __hostname__:memory-percent
        swap-percent:
{% if grains["virtual"] == "lxc"|lower or grains["oscodename"] in ["precise"] %}
          disabled: True
{% endif %}
          cmd: /opt/sensu-plugins-ruby/embedded/bin/check-swap-percent.rb -w 70 -c 80
          severity_per_retcode:
            1: minor
            2: major
          service: memory
          resource: __hostname__:swap-percent
        swap-usage:
{% if grains["virtual"] == "lxc"|lower or grains["oscodename"] in ["precise"] %}
          disabled: True
{% endif %}
          cmd: /opt/sensu-plugins-ruby/embedded/bin/check-swap.rb -w 1024 -c 2048
          severity_per_retcode:
            1: minor
            2: major
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
        severity: major
      checks:
        netfilter-conntrack:
{% if grains["oscodename"] in ["precise"] %}
          disabled: True
{% endif %}
          # Checking not salt["file.file_exists"]("/proc/sys/net/netfilter/nf_conntrack_max") will not work in pillar as pillar is rendered on salt-master/salt-ssh runner, not minion.
          # So check it in the check runtime.
          cmd: if [[ -r /proc/sys/net/netfilter/nf_conntrack_max ]]; then /opt/sensu-plugins-ruby/embedded/bin/check-netfilter-conntrack.rb -w 80 -c 90; fi
          severity_per_retcode:
            1: major
            2: critical
          service: network
          resource: __hostname__:netfilter-conntrack
        iptables_input_drop:
{% if grains["oscodename"] in ["precise"] %}
          disabled: True
{% endif %}
          cmd: iptables -w -S | grep -q -e "-P INPUT DROP"
          #severity: security
          severity: minor
          service: network
          resource: __hostname__:iptables_input_drop
        iptables_open_from_any:
{% if grains["oscodename"] in ["precise"] %}
          disabled: True
{% endif %}
          # we check rules that are without source, exclude standard ufw rules, exclude open port from exclusion list file
          cmd: IPT_RULES=$(iptables -w -S | grep -e "-j ACCEPT" | grep -v -e "-s " | grep -v -f /opt/sysadmws/cmd_check_alert/checks/exclude_network_iptables_open_from_any_std_ufw.txt | grep -v -f /opt/sysadmws/cmd_check_alert/checks/exclude_network_iptables_open_from_any_safe.txt); if [[ -n "$IPT_RULES" ]]; then echo "${IPT_RULES}"; ( exit 1 ); fi
          #severity: security
          severity: minor
          service: network
          resource: __hostname__:iptables_open_from_any
    files:
      /opt/sysadmws/cmd_check_alert/checks/exclude_network_iptables_open_from_any_std_ufw.txt:
        std_ufw: |
          OUTPUT
          FORWARD
          ufw-before-forward
          ufw-before-input
          ufw-before-output
          ufw-skip-to-policy-forward
          ufw-skip-to-policy-output
          ufw-track-forward
          ufw-track-output
          ufw-user-limit-accept
      /opt/sysadmws/cmd_check_alert/checks/exclude_network_iptables_open_from_any_safe.txt:
        lxd: |
          -i lxdbr0
        k8s_cali: |
          -A cali
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
{% if grains["oscodename"] in ["precise"] %}
          disabled: True
{% endif %}
          cmd: /opt/sensu-plugins-ruby/embedded/bin/check-fstab-mounts.rb
          severity: critical
          service: disk
          resource: __hostname__:fstab-mounts
        smart:
{% if grains["virtual"] != "physical" or grains["oscodename"] in ["precise"] %}
          disabled: True
{% endif %}
          cmd: /opt/sensu-plugins-ruby/embedded/bin/check-smart.rb
          severity_per_retcode:
            1: major
            2: critical
          service: disk
          resource: __hostname__:smart
        raid:
{% if grains["virtual"] != "physical" or grains["oscodename"] in ["precise"] %}
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
{% if grains["oscodename"] == "focal" or (grains["oscodename"] == "bionic" and grains["virtual"] != "lxc"|lower) %}
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
{% if not (grains["oscodename"] == "focal" or (grains["oscodename"] == "bionic" and grains["virtual"] != "lxc"|lower)) %}
          disabled: True
{% endif %}
          cmd: CVESCAN_OUT=$(/root/.local/bin/cvescan -p all); if echo "${CVESCAN_OUT}" | grep -q -e "Fixes Available by.*apt-get upgrade.* 0$"; then echo "${CVESCAN_OUT}"; ( exit 0 ); else echo "${CVESCAN_OUT}"; ( exit 2 ); fi
          severity_per_retcode:
            1: warning
            #2: security
            2: minor
          service: pkg
          resource: __hostname__:cvescan
        yum_security:
{% if grains["os_family"] != "RedHat" %}
          disabled: True
{% endif %}
          cmd: yum -q makecache && if yum --cacheonly updateinfo summary updates | grep -q "Security"; then yum --cacheonly updateinfo list updates | grep "/Sec."; yum --cacheonly updateinfo summary updates | grep "Security"; ( exit 2 ); else true; fi
          severity_per_retcode:
            1: warning
            #2: security
            2: minor
          service: pkg
          resource: __hostname__:yum_security
