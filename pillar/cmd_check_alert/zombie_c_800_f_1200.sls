{% if grains["osarch"] in ["arm64"] %}
  {%- set ruby_prefix = "source /usr/local/rvm/scripts/rvm && /usr/local/rvm/gems/ruby-2.4.10/bin" %}
{% else %}
  {%- set ruby_prefix = "/opt/sensu-plugins-ruby/embedded/bin" %}
{% endif %}
cmd_check_alert:
  syshealth:
    config:
      checks:
        zombie:
          cmd_override: {{ ruby_prefix }}/check-process.rb -s Z -W 0 -C 0 -w 800 -c 1200
