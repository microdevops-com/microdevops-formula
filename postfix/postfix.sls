{% if (pillar['postfix'] is defined) and (pillar['postfix'] is not none) %}
  {%- if (pillar['postfix']['enabled'] is defined) and (pillar['postfix']['enabled'] is not none) and (pillar['postfix']['enabled']) %}
postfix_install:
  pkg.installed:
    - pkgs:
      - postfix
      - bsd-mailx
      - heirloom-mailx

exim_purge:
  pkg.purged:
    - pkgs:
      - exim4
      - exim4-base
      - exim4-config
      - exim4-daemon-light

exim_purge_2:
  cmd.run:
    - name: 'dpkg --purge exim4 exim4-base exim4-config exim4-daemon-light'
  {%- endif %}
{% endif %}
