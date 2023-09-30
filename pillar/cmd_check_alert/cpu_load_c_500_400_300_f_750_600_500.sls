{% if grains["osarch"] in ["arm64"] %}
  {%- set ruby_prefix = "source /usr/local/rvm/scripts/rvm && /usr/local/rvm/gems/ruby-2.4.0/bin" %}
{% else %}
  {%- set ruby_prefix = "/opt/sensu-plugins-ruby/embedded/bin" %}
{% endif %}
cmd_check_alert:
  cpu:
    config:
      checks:
        load-average:
          cmd_override: {{ ruby_prefix }}/check-load.rb --warn 5,4,3 --crit 7.5,6,5
