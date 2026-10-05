{% if grains["osarch"] in ["arm64"] %}
  {%- set ruby_prefix = "source /usr/local/rvm/scripts/rvm && /usr/local/rvm/gems/ruby-2.4.10/bin" %}
{% else %}
  {%- set ruby_prefix = "/opt/sensu-plugins-ruby/embedded/bin" %}
{% endif %}
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
{% if (grains["virtual"]|lower == "lxc" or grains["virtual"]|lower == "container") %}
          # We need to catch this only on host machines as containers share the kernel with the host
          disabled: True
{% endif %}
          cmd: :; ! dmesg -T | grep -v "veth" | grep -i "hardware.*error" -m 10
          service: hardware
          resource: __hostname__:hardware
        hardware-nvme:
{% if (grains["virtual"]|lower == "lxc" or grains["virtual"]|lower == "container") %}
          # We need to catch this only on host machines as containers share the kernel with the host
          disabled: True
{% endif %}
          cmd: :; ! dmesg -T | grep -v "veth" | grep -i "nvme.*err" -m 10
          service: disk
          resource: __hostname__:hardware-nvme
        hardware-completion-loop-timeout:
{% if (grains["virtual"]|lower == "lxc" or grains["virtual"]|lower == "container") %}
          # We need to catch this only on host machines as containers share the kernel with the host
          disabled: True
{% endif %}
{% if grains["oscodename"] in ["bookworm", "noble", "trixie"] %}
          cmd: :; ! journalctl -k | grep -i "Completion-Wait loop timed out" -m 10
{% else %}
          cmd: :; ! grep -i "Completion-Wait loop timed out" -m 10 /var/log/kern.log
{% endif %}
          service: hardware
          resource: __hostname__:hardware-completion-loop-timeout
        hardware-soft-lockup:
{% if (grains["virtual"]|lower == "lxc" or grains["virtual"]|lower == "container") %}
          # We need to catch this only on host machines as containers share the kernel with the host
          disabled: True
{% endif %}
{% if grains["oscodename"] in ["bookworm", "noble", "trixie"] %}
          cmd: :; ! journalctl -k | grep -i "watchdog.*BUG.*soft lockup - CPU.*stuck" -m 10
{% else %}
          cmd: :; ! grep -i "watchdog.*BUG.*soft lockup - CPU.*stuck" -m 10 /var/log/kern.log
{% endif %}
          service: hardware
          resource: __hostname__:hardware-soft-lockup
        hardware-cpu-temperature-throttling:
{% if (grains["virtual"]|lower == "lxc" or grains["virtual"]|lower == "container") %}
          # We need to catch this only on host machines as containers share the kernel with the host
          disabled: True
{% endif %}
          cmd: :; ! dmesg -T | grep -v "veth" | grep -i -e "temperature above threshold" -e "cpu clock throttled" -m 10
          service: cpu
          resource: __hostname__:hardware-cpu-temperature-throttling
        oom:
          cmd: :; ! dmesg -T | grep -v "veth" | grep -i -e "Out of memory" -e "oom"
          service: os
          resource: __hostname__:oom
{%- if grains.get("oscodename","") not in ["precise"] %}
        zombie:
          cmd: {{ ruby_prefix }}/check-process.rb -s Z -W 0 -C 0 -w 10 -c 15
          service: os
          resource: __hostname__:zombie
          severity_per_retcode:
            1: major
            2: critical
{%- endif %}
        coredump:
{% if (grains["virtual"]|lower == "lxc" or grains["virtual"]|lower == "container") %}
          # We need to catch this only on host machines as containers share the kernel with the host
          disabled: True
{% endif %}
          cmd: :; ! dmesg -T | grep -v "veth" | grep -i "core dump" -m 10
          service: os
          resource: __hostname__:coredump
        segfault:
{% if (grains["virtual"]|lower == "lxc" or grains["virtual"]|lower == "container") %}
          # We need to catch this only on host machines as containers share the kernel with the host
          disabled: True
{% endif %}
          cmd: :; ! dmesg -T | grep -v "veth" | grep -i "segfault" -m 10 | grep -v -i -e "ebpf" -e "netdata"
          service: os
          resource: __hostname__:segfault
        ping-ipv4:
          cmd: for t in 1.1.1.1 8.8.8.8 9.9.9.9; do ping -4 -c2 -i0.5 -W2 $t && exit 0; done; exit 1
          service: os
          resource: __hostname__:ping-ipv4
{%- set global_ipv6 = [] %}
{%- for a in grains.get("ipv6", []) %}
  {%- if a != "::1" and not (a|lower).startswith(("fe8", "fe9", "fea", "feb", "fc", "fd")) %}
    {%- do global_ipv6.append(a) %}
  {%- endif %}
{%- endfor %}
        ping-ipv6:
{%- if not global_ipv6 %}
          # Only hosts with a global IPv6 address (not loopback, link-local or ULA) are expected to reach IPv6 targets
          disabled: True
{%- endif %}
          cmd: ip -6 route show default; for t in 2606:4700:4700::1111 2001:4860:4860::8888 2620:fe::fe; do ping -6 -c2 -i0.5 -W2 $t && exit 0; done; exit 1
          service: os
          resource: __hostname__:ping-ipv6
        dns-resolve:
          cmd: grep -h nameserver /etc/resolv.conf; timeout 2 resolvectl dns 2>/dev/null | grep -v ':$'; for n in google.com cloudflare.com quad9.net; do timeout 3 getent hosts $n && exit 0; done; exit 1
          service: os
          resource: __hostname__:dns-resolve
{%- if grains.get("oscodename","") not in ["precise"] %}
        clock-synchronized:
          cmd: timedatectl status | grep -i "synchronized" | grep -i "yes"
          service: os
          resource: __hostname__:clock-synchronized
{%- endif %}
