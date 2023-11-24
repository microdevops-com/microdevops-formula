cmd_check_alert:
  syshealth:
    config:
      checks:
        hardware:
          cmd_override: :; ! dmesg -T | grep -i "hardware.*error" -m 10 | grep -v -i -e "Machine check events logged"
