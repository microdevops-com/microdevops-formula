cmd_check_alert:
  syshealth:
    config:
      checks:
        oom:
          cmd_override: :; ! dmesg -T | grep -v "veth" | grep -i -e "oom-kill" | grep -e "$(hostname -f)"
