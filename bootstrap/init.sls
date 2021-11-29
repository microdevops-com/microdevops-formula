include:
{% if grains["oscodename"] in ["bionic", "focal", "bullseye"] %}
  - .{{ grains["oscodename"] }}
{% elif grains["osfinger"] == "CentOS Linux-7" %}
  - .centos7
{% endif %}
  - .files
  - .root_password_hash
