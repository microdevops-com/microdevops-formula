cmd_check_alert:
  syshealth:
    config:
      checks:
        hardware-nvme:
          cmd_override: :; ! dmesg -T | grep -i "nvme.*error:" -m 10 | grep -v -i -e "corrected"
