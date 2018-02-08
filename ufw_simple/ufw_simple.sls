{% if (pillar['ufw_simple'] is defined) and (pillar['ufw_simple'] is not none) %}
  {%- if (pillar['ufw_simple']['enabled'] is defined) and (pillar['ufw_simple']['enabled'] is not none) and (pillar['ufw_simple']['enabled']) %}

    {%- if (grains['oscodename'] == 'precise') %}
python_snakes_repo:
  pkgrepo.managed:
    - name: deb http://ppa.launchpad.net/fkrull/deadsnakes/ubuntu precise main
    - dist: precise
    - file: /etc/apt/sources.list.d/fkrull-deadsnakes-precise.list
    - keyserver: keyserver.ubuntu.com
    - keyid: DB82666C
    - refresh_db: true

python_33_installed:
  pkg.latest:
    - pkgs:
        - python3.3

python_33_inst_alt:
  alternatives.install:
    - name: 'python3'
    - link: '/usr/bin/python3'
    - path: '/usr/bin/python3.3'
    - priority: 30
    - require:
        - pkg: python_33_installed

python_33_set_alt:
  alternatives.set:
    - name: 'python3'
    - path: '/usr/bin/python3.3'
    - require:
        - pkg: python_33_installed

ufw_simple_dep_deb:
  pkg.installed:
    - sources:
      - init-system-helpers: 'salt://ufw_simple/files/init-system-helpers_1.18_all.deb'
    {%- endif %}

    {%- if (grains['oscodename'] == 'trusty') %}
ufw_simple_dep_deb:
  pkg.installed:
    - sources:
      - init-system-helpers: 'salt://ufw_simple/files/init-system-helpers_1.18_all.deb'
    {%- endif %}

    {%- if (grains['oscodename'] == 'precise') %}
ufw_simple_update_deb:
  pkg.installed:
    - sources:
      - ufw: 'salt://ufw_simple/files/ufw_0.35-4_all_deadsnakes.deb'
    {%- else %}
ufw_simple_update_deb:
  pkg.installed:
    - sources:
      - ufw: 'salt://ufw_simple/files/ufw_0.35-4_all.deb'
    {%- endif %}

    # not managed nat - to be removed
    {%- if (pillar['ufw_simple']['nat_enabled'] is defined) and (pillar['ufw_simple']['nat_enabled'] is not none) and (pillar['ufw_simple']['nat_enabled']) %}
ufw_simple_nat_file_1:
  file.managed:
    - name: '/etc/ufw/sysctl.conf'
    - source: 'salt://ufw_simple/files/ufw_sysctl.conf'
    - mode: 0644

ufw_simple_nat_file_2:
  file.managed:
    - name: '/etc/default/ufw'
    - source: 'salt://ufw_simple/files/etc_default_ufw'
    - mode: 0644

ufw_simple_restart:
  cmd.run:
    - name: 'ufw disable && sleep 5 && ufw enable'
    - runas: root
    - onchanges:
      - file: '/etc/ufw/sysctl.conf'
      - file: '/etc/default/ufw'
    {%- endif %}

    # managed nat
    {%- if
           (pillar['ufw_simple']['nat'] is defined) and (pillar['ufw_simple']['nat'] is not none) and
           (pillar['ufw_simple']['nat']['enabled'] is defined) and (pillar['ufw_simple']['nat']['enabled'] is not none) and (pillar['ufw_simple']['nat']['enabled'])
    %}
ufw_simple_nat_managed_file_1:
  file.managed:
    - name: '/etc/ufw/sysctl.conf'
    - source: 'salt://ufw_simple/files/ufw_sysctl.conf'
    - mode: 0644

ufw_simple_nat_managed_file_2:
  file.managed:
    - name: '/etc/default/ufw'
    - source: 'salt://ufw_simple/files/etc_default_ufw'
    - mode: 0644

ufw_simple_nat_managed_file_3:
  file.managed:
    - name: '/etc/ufw/before.rules'
    - source: 'salt://ufw_simple/files/before.rules'
    - mode: 0640
    - template: jinja
    - defaults:
      {%- if (pillar['ufw_simple']['nat']['masquerade'] is defined) and (pillar['ufw_simple']['nat']['masquerade'] is not none) %}
        masquerade: |
        {%- for m_key, m_val in pillar['ufw_simple']['nat']['masquerade'].items()|sort %}
          # {{ m_key }}
          -A POSTROUTING -s {{ m_val['source'] }} -o {{ m_val['out'] }} -j MASQUERADE
        {%- endfor %}
      {%- else %}
        masquerade: '# empty'
      {%- endif %}
      {%- if (pillar['ufw_simple']['nat']['dnat'] is defined) and (pillar['ufw_simple']['nat']['dnat'] is not none) %}
        dnat: |
        {%- for d_key, d_val in pillar['ufw_simple']['nat']['dnat'].items()|sort %}
          # {{ d_key }}
          {%- if (d_val['from'] is defined) and (d_val['from'] is not none) %}
            {%- set src_block = '-s ' ~ d_val['from'] %}
          {%- else %}
            {%- set src_block = ' ' %}
          {%- endif %}
          -A PREROUTING -i {{ d_val['in'] }} {{ src_block }} -p {{ d_val['proto'] }} --dport {{ d_val['dport'] }} -j DNAT --to-destination {{ d_val['to'] }}
        {%- endfor %}
      {%- else %}
        dnat: '# empty'
      {%- endif %}
      {%- if (pillar['ufw_simple']['nat']['snat'] is defined) and (pillar['ufw_simple']['nat']['snat'] is not none) %}
        snat: |
        {%- for s_key, s_val in pillar['ufw_simple']['nat']['snat'].items()|sort %}
          # {{ s_key }}
          {%- if (s_val['from'] is defined) and (s_val['from'] is not none) %}
            {%- set src_block = '-s ' ~ s_val['from'] %}
          {%- else %}
            {%- set src_block = ' ' %}
          {%- endif %}
          -A POSTROUTING -o {{ s_val['out'] }} {{ src_block }} -p {{ s_val['proto'] }} --dport {{ s_val['dport'] }} -j SNAT --to {{ s_val['to'] }}
        {%- endfor %}
      {%- else %}
        snat: '# empty'
      {%- endif %}
      {%- if (pillar['ufw_simple']['nat']['redirect'] is defined) and (pillar['ufw_simple']['nat']['redirect'] is not none) %}
        redirect: |
        {%- for r_key, r_val in pillar['ufw_simple']['nat']['redirect'].items()|sort %}
          # {{ r_key }}
          {%- if (r_val['src'] is defined) and (r_val['src'] is not none) %}
            {%- set src_block = '--src ' ~ r_val['src'] %}
          {%- else %}
            {%- set src_block = ' ' %}
          {%- endif %}
          {%- if (r_val['dst'] is defined) and (r_val['dst'] is not none) %}
            {%- set dst_block = '--dst ' ~ r_val['dst'] %}
          {%- else %}
            {%- set dst_block = ' ' %}
          {%- endif %}
          -A PREROUTING -i {{ r_val['in'] }} {{ src_block }} {{ dst_block }} -p {{ r_val['proto'] }} --dport {{ r_val['dport'] }} -j REDIRECT --to-ports {{ r_val['to_ports'] }}
        {%- endfor %}
      {%- else %}
        redirect: '# empty'
      {%- endif %}
      {%- if (pillar['ufw_simple']['nat']['custom'] is defined) and (pillar['ufw_simple']['nat']['custom'] is not none) %}
        {%- if (pillar['ufw_simple']['nat']['custom']['nat'] is defined) and (pillar['ufw_simple']['nat']['custom']['nat'] is not none) %}
          custom_nat: {{ pillar['ufw_simple']['nat']['custom']['nat'] | yaml_encode }}
        {%- else %}
          custom_nat: '# empty'
        {%- endif %}
        {%- if (pillar['ufw_simple']['nat']['custom']['filter'] is defined) and (pillar['ufw_simple']['nat']['custom']['filter'] is not none) %}
          custom_filter: {{ pillar['ufw_simple']['nat']['custom']['filter'] | yaml_encode }}
        {%- else %}
          custom_filter: '# empty'
        {%- endif %}
      {%- endif %}

ufw_simple_nat_managed_restart:
  cmd.run:
    - name: 'ufw disable && sleep 5 && ufw enable'
    - runas: root
    - onchanges:
      - file: '/etc/ufw/sysctl.conf'
      - file: '/etc/default/ufw'
      - file: '/etc/ufw/before.rules'
    {%- endif %}

    {%- if  (pillar['ufw_simple']['logging'] is defined) and (pillar['ufw_simple']['logging'] is not none) %}
ufw_simple_set_logging:
  cmd.run:
    - name: {{ 'ufw logging ' ~ pillar['ufw_simple']['logging'] }}
    - runas: root
    {%- endif %}

    {%- if  (pillar['ufw_simple']['allow'] is defined) and (pillar['ufw_simple']['allow'] is not none) %}
      {%- set item_action = 'allow' %}
      {%- set item_delete = '' %}
      {%- set pillar_context = pillar['ufw_simple']['allow'] %}
      {% include 'ufw_simple/loop.jinja' with context %}
    {%- endif %}

    {%- if  (pillar['ufw_simple']['deny'] is defined) and (pillar['ufw_simple']['deny'] is not none) %}
      {%- set item_action = 'deny' %}
      {%- set item_delete = '' %}
      {%- set pillar_context = pillar['ufw_simple']['deny'] %}
      {% include 'ufw_simple/loop.jinja' with context %}
    {%- endif %}

    {%- if  (pillar['ufw_simple']['reject'] is defined) and (pillar['ufw_simple']['reject'] is not none) %}
      {%- set item_action = 'reject' %}
      {%- set item_delete = '' %}
      {%- set pillar_context = pillar['ufw_simple']['reject'] %}
      {% include 'ufw_simple/loop.jinja' with context %}
    {%- endif %}

    {%- if  (pillar['ufw_simple']['limit'] is defined) and (pillar['ufw_simple']['limit'] is not none) %}
      {%- set item_action = 'limit' %}
      {%- set item_delete = '' %}
      {%- set pillar_context = pillar['ufw_simple']['limit'] %}
      {% include 'ufw_simple/loop.jinja' with context %}
    {%- endif %}

    {%- if  (pillar['ufw_simple']['limit_in'] is defined) and (pillar['ufw_simple']['limit_in'] is not none) %}
      {%- set item_action = 'limit_in' %}
      {%- set item_delete = '' %}
      {%- set pillar_context = pillar['ufw_simple']['limit_in'] %}
      {% include 'ufw_simple/loop.jinja' with context %}
    {%- endif %}

    {%- if  (pillar['ufw_simple']['limit_out'] is defined) and (pillar['ufw_simple']['limit_out'] is not none) %}
      {%- set item_action = 'limit_out' %}
      {%- set item_delete = '' %}
      {%- set pillar_context = pillar['ufw_simple']['limit_out'] %}
      {% include 'ufw_simple/loop.jinja' with context %}
    {%- endif %}

    {# delete #}
    {%- if (pillar['ufw_simple']['delete'] is defined) and (pillar['ufw_simple']['delete'] is not none) %}
      {%- if  (pillar['ufw_simple']['delete']['allow'] is defined) and (pillar['ufw_simple']['delete']['allow'] is not none) %}
        {%- set item_action = 'allow' %}
        {%- set item_delete = 'delete' %}
        {%- set pillar_context = pillar['ufw_simple']['delete']['allow'] %}
        {% include 'ufw_simple/loop.jinja' with context %}
      {%- endif %}

      {%- if  (pillar['ufw_simple']['delete']['deny'] is defined) and (pillar['ufw_simple']['delete']['deny'] is not none) %}
        {%- set item_action = 'deny' %}
        {%- set item_delete = 'delete' %}
        {%- set pillar_context = pillar['ufw_simple']['delete']['deny'] %}
        {% include 'ufw_simple/loop.jinja' with context %}
      {%- endif %}

      {%- if  (pillar['ufw_simple']['delete']['reject'] is defined) and (pillar['ufw_simple']['delete']['reject'] is not none) %}
        {%- set item_action = 'reject' %}
        {%- set item_delete = 'delete' %}
        {%- set pillar_context = pillar['ufw_simple']['delete']['reject'] %}
        {% include 'ufw_simple/loop.jinja' with context %}
      {%- endif %}

      {%- if  (pillar['ufw_simple']['delete']['limit'] is defined) and (pillar['ufw_simple']['delete']['limit'] is not none) %}
        {%- set item_action = 'limit' %}
        {%- set item_delete = 'delete' %}
        {%- set pillar_context = pillar['ufw_simple']['delete']['limit'] %}
        {% include 'ufw_simple/loop.jinja' with context %}
      {%- endif %}

      {%- if  (pillar['ufw_simple']['delete']['limit_in'] is defined) and (pillar['ufw_simple']['delete']['limit_in'] is not none) %}
        {%- set item_action = 'limit_in' %}
        {%- set item_delete = 'delete' %}
        {%- set pillar_context = pillar['ufw_simple']['delete']['limit_in'] %}
        {% include 'ufw_simple/loop.jinja' with context %}
      {%- endif %}

      {%- if  (pillar['ufw_simple']['delete']['limit_out'] is defined) and (pillar['ufw_simple']['delete']['limit_out'] is not none) %}
        {%- set item_action = 'limit_out' %}
        {%- set item_delete = 'delete' %}
        {%- set pillar_context = pillar['ufw_simple']['delete']['limit_out'] %}
        {% include 'ufw_simple/loop.jinja' with context %}
      {%- endif %}
    {%- endif %}

ufw_simple_enable:
  cmd.run:
    - name: 'ufw enable'
    - runas: root

  {%- endif %}
{% endif %}
