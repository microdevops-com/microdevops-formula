{% if pillar["bootstrap"] is defined and "cron" in pillar["bootstrap"] %}
  
  {%- from "_include/cron_manager/macros.jinja" import cron_manager %}
  {{ cron_manager(cron = pillar["bootstrap"]["cron"], prefix = "bootstrap") }} 

{% endif %}
