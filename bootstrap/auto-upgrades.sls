{% if grains["os"] in ["Ubuntu", "Debian"] %}
bootstrap_auto-upgrades:

  {%- if pillar["bootstrap"] is defined and "auto-upgrades" in pillar["bootstrap"] %}
  file.managed:
    - name: /etc/apt/apt.conf.d/20auto-upgrades
    - mode: 0644
    - contents_pillar: bootstrap:auto-upgrades

  {%- else %}
  file.managed:
    # By default, auto-upgrades are disabled
    - name: /etc/apt/apt.conf.d/20auto-upgrades
    - mode: 0644
    - contents: |
        APT::Periodic::Update-Package-Lists "0";
        APT::Periodic::Unattended-Upgrade "0";

  {%- endif %}

{% endif %}
