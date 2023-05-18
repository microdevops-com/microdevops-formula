{% if pillar["docker-ce"] is defined and "daily_image_prune" in pillar["docker-ce"] and pillar["docker-ce"]["daily_image_prune"] %}
docker-ce_image_prune_daily:
  cron.present:
    - identifier: docker_image_prune_daily
    - user: root
    - minute: '23'
    - hour: '2'
    - daymonth: '*'
    - month: '*'
    - dayweek: '*'
    - cmd: $(which docker) image prune -a --force
{% endif %}
