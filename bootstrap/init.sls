include:
{% if grains["oscodename"] in ["bionic", "focal", "bullseye", "jammy", "bookworm", "noble"] %}
  - .{{ grains["oscodename"] }}
{% elif grains["osfinger"] == "CentOS Linux-7" %}
  - .centos7
{% endif %}
  - .root_password_hash
  - .pkgs
  - .files
  - .cron
  - .salt-ssh_cleaner
  - .tz
  - .locale
  - .auto-upgrades
  - .service
  - .sshd_prohibit_password
