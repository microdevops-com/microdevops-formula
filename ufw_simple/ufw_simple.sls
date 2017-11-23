{% if (pillar['ufw_simple'] is defined) and (pillar['ufw_simple'] is not none) %}
  {%- if (pillar['ufw_simple']['enabled'] is defined) and (pillar['ufw_simple']['enabled'] is not none) and (pillar['ufw_simple']['enabled']) %}

    {%- if (grains['oscodename'] == 'trusty') %}
ufw_simple_dep_deb:
  pkg.installed:
    - sources:
      - init-system-helpers: 'salt://ufw_simple/files/init-system-helpers_1.18_all.deb'
    {%- endif %}

ufw_simple_update_deb:
  pkg.installed:
    - sources:
      - ufw: 'salt://ufw_simple/files/ufw_0.35-4_all.deb'

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
      {%- for item_name, item_params in pillar['ufw_simple']['allow'].items() %}
        {%- set item_action = 'allow' %}
        {% include 'ufw_simple/loop.jinja' with context %}
      {%- endfor %}
    {%- endif %}

    {%- if  (pillar['ufw_simple']['deny'] is defined) and (pillar['ufw_simple']['deny'] is not none) %}
      {%- for item_name, item_params in pillar['ufw_simple']['deny'].items() %}
        {%- set item_action = 'deny' %}
        {% include 'ufw_simple/loop.jinja' with context %}
      {%- endfor %}
    {%- endif %}

    {%- if  (pillar['ufw_simple']['reject'] is defined) and (pillar['ufw_simple']['reject'] is not none) %}
      {%- for item_name, item_params in pillar['ufw_simple']['reject'].items() %}
        {%- set item_action = 'reject' %}
        {% include 'ufw_simple/loop.jinja' with context %}
      {%- endfor %}
    {%- endif %}

    {%- if  (pillar['ufw_simple']['limit'] is defined) and (pillar['ufw_simple']['limit'] is not none) %}
      {%- for item_name, item_params in pillar['ufw_simple']['limit'].items() %}
        {%- set item_action = 'limit' %}
        {% include 'ufw_simple/loop.jinja' with context %}
      {%- endfor %}
    {%- endif %}

    {%- if  (pillar['ufw_simple']['limit_in'] is defined) and (pillar['ufw_simple']['limit_in'] is not none) %}
      {%- for item_name, item_params in pillar['ufw_simple']['limit_in'].items() %}
        {%- set item_action = 'limit_in' %}
        {% include 'ufw_simple/loop.jinja' with context %}
      {%- endfor %}
    {%- endif %}

    {%- if  (pillar['ufw_simple']['limit_out'] is defined) and (pillar['ufw_simple']['limit_out'] is not none) %}
      {%- for item_name, item_params in pillar['ufw_simple']['limit_out'].items() %}
        {%- set item_action = 'limit_out' %}
        {% include 'ufw_simple/loop.jinja' with context %}
      {%- endfor %}
    {%- endif %}

ufw_simple_enable:
  cmd.run:
    - name: 'ufw enable'
    - runas: root

  {%- endif %}
{% endif %}
