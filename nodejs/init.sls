{% if pillar["nodejs"] is defined %}

nodejs_repo:
  pkg.installed:
    - pkgs: [curl, gpg]
  cmd.run:
    - name: |
        curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /usr/share/keyrings/nodesource.gpg
    - creates: /usr/share/keyrings/nodesource.gpg
  file.managed:
    - name: /etc/apt/sources.list.d/nodesource.list
    - contents: |
        deb [arch={{ grains["osarch"] }} signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_{{ pillar["nodejs"]["version"] }}.x nodistro main

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
