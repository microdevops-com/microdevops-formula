cmd_check_alert:
  cpu:
    config:
      checks:
        load-average:
          cmd_override: {{ ruby_prefix }}/check-load.rb --warn 1.5,0.9,0.6 --crit 2.5,1.5,1
