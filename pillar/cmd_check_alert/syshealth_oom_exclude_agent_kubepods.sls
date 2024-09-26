cmd_check_alert:
  syshealth:
    config:
      checks:
        oom:
          cmd_override: :; ! dmesg -T | grep -v "veth" | grep -v -e "kubepods" -e "(agent)" | grep -i -e "Out of memory"
