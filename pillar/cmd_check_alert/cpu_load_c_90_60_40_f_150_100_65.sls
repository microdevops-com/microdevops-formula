cmd_check_alert:
  cpu:
    config:
      checks:
        load-average:
          cmd_override: {{ ruby_prefix }}/check-load.rb --warn 0.9,0.6,0.4 --crit 1.5,1,0.65
