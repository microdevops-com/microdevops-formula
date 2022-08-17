{% if pillar["nodejs"] is defined %}

nodejs_repo:
  pkgrepo.managed:
    - humanname: NodeSource Node.js
    - name: deb https://deb.nodesource.com/node_{{ pillar["nodejs"]["version"] }}.x focal main
    - file: /etc/apt/sources.list.d/nodesource.list
    - key_url: https://deb.nodesource.com/gpgkey/nodesource.gpg.key
    - clean_file: True

nodejs_pkg:
  pkg.latest:
    - refresh: True
    - pkgs:
        - nodejs

  {%- if "npm" in pillar["nodejs"] and "install" in pillar["nodejs"]["npm"] %}
    {%- for pkg in pillar["nodejs"]["npm"]["install"] %}
nodejq_npm_install_{{ loop.index }}:
  cmd.run:
    - name: npm install --global {{ pkg }}

    {%- endfor %}
  {%- endif %}
{% endif %}
