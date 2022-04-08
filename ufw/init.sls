{% if pillar["ufw"] is defined and pillar["_errors"] is not defined %}

  # Import deprecated ufw_simple rules if enabled
  {%- if "import_ufw_simple" in pillar["ufw"] and pillar["ufw"]["import_ufw_simple"] and pillar["ufw_simple"] is defined %}
    # allow, deny, reject, limit
    {%- for rule_action in ["allow", "deny", "reject", "limit"] %}
      {%- if rule_action in pillar["ufw_simple"] %}
        {%- if rule_action not in pillar["ufw"] %}
          {%- do pillar["ufw"].update({ rule_action: {} }) %}
        {%- endif %}
        {%- do pillar["ufw"][rule_action].update(pillar["ufw_simple"][rule_action]) %}
      {%- endif %}
    {%- endfor %}
    # nat
    {%- if "nat" in pillar["ufw_simple"] %}
      {%- if "nat" not in pillar["ufw"] %}
        {%- do pillar["ufw"].update({ "nat": {} }) %}
        {%- do pillar["ufw"]["nat"].update({ "management_disabled": pillar["ufw_simple"]["nat"]["management_disabled"] }) %}
      {%- endif %}
      # masquerade, dnat, snat, redirect
      {%- for nat_action in ["masquerade", "dnat", "snat", "redirect"] %}
        {%- if nat_action in pillar["ufw_simple"]["nat"] %}
          {%- if nat_action not in pillar["ufw"]["nat"] %}
            {%- do pillar["ufw"]["nat"].update({ nat_action: {} }) %}
          {%- endif %}
          {%- do pillar["ufw"]["nat"][nat_action].update(pillar["ufw_simple"]["nat"][nat_action]) %}
        {%- endif %}
      {%- endfor %}
    {%- endif %}
    # custom
    {%- if "custom" in pillar["ufw_simple"] %}
      {%- if "custom" not in pillar["ufw"] %}
        {%- do pillar["ufw"].update({ "custom": {} }) %}
      {%- endif %}
      # nat only if in ufw not set
      {%- if "nat" in pillar["ufw_simple"]["custom"] and "nat" not in pillar["ufw"]["custom"]  %}
        {%- do pillar["ufw"]["custom"].update({ "nat": pillar["ufw_simple"]["custom"]["nat"] }) %}
      {%- endif %}
      # filter only if in ufw not set
      {%- if "filter" in pillar["ufw_simple"]["custom"] and "filter" not in pillar["ufw"]["custom"]  %}
        {%- do pillar["ufw"]["custom"].update({ "filter": pillar["ufw_simple"]["custom"]["filter"] }) %}
      {%- endif %}
    {%- endif %}
  {%- endif %}
  
  {%- if "nat" in pillar["ufw"] and "management_disabled" in pillar["ufw"]["nat"] and pillar["ufw"]["nat"]["management_disabled"] %}
    {%- set manage_nat = False %}
  {%- else %}
    {%- set manage_nat = True %}
  {%- endif %}

ufw_pkg_latest:
  pkg.latest:
    - pkgs:
        - ufw

  # Enable ip forwarding if nat or custom nat rules
ufw_ip_fwd_managed_file_1:
  file.managed:
    - name: /etc/ufw/sysctl.conf
    - source: salt://ufw/files/etc_ufw_sysctl.conf
    - mode: 0644
    - template: jinja
    - defaults:
  {%- if "nat" in pillar["ufw"] or ("custom" in pillar["ufw"] and "nat" in pillar["ufw"]["custom"]) %}
        IP_FWD: |
          net/ipv4/ip_forward=1
          net/ipv6/conf/default/forwarding=1
          net/ipv6/conf/all/forwarding=1
  {%- else %}
        IP_FWD: |
          #net/ipv4/ip_forward=1
          #net/ipv6/conf/default/forwarding=1
          #net/ipv6/conf/all/forwarding=1
  {%- endif %}

ufw_ip_fwd_managed_file_2:
  file.managed:
    - name: /etc/default/ufw
    - source: salt://ufw/files/etc_default_ufw
    - mode: 0644
    - template: jinja
    - defaults:
  {%- if "nat" in pillar["ufw"] or ("custom" in pillar["ufw"] and "nat" in pillar["ufw"]["custom"]) %}
        DEFAULT_FORWARD_POLICY: ACCEPT
        IPT_MODULES: nf_conntrack_ftp nf_nat_ftp nf_conntrack_netbios_ns
  {%- else %}
        DEFAULT_FORWARD_POLICY: DROP
        IPT_MODULES: ""
  {%- endif %}

  # Manage /etc/ufw/before.rules if nat or custom rules
ufw_before_rules_managed:
  file.managed:
    - name: /etc/ufw/before.rules
    - source: salt://ufw/files/etc_ufw_before.rules
    - mode: 0640
    - template: jinja
    - defaults:
    # nat_flush
  {%- if manage_nat %}
        nat_flush: "-F"
  {%- else %}
        nat_flush: "# management disabled"
  {%- endif %}
    # masquerade
  {%- if "nat" in pillar["ufw"] and "masquerade" in pillar["ufw"]["nat"] and manage_nat %}
        masquerade: |
    {%- for m_key, m_val in pillar["ufw"]["nat"]["masquerade"].items()|sort %}
          # {{ m_key }}
      {%- if "source" in m_val %}
          -A POSTROUTING -s {{ m_val["source"] }} -o {{ m_val["out"] }} -j MASQUERADE
      {%- else %}
          -A POSTROUTING -o {{ m_val["out"] }} -j MASQUERADE
      {%- endif %}
    {%- endfor %}
  {%- else %}
        masquerade: "# empty"
  {%- endif %}
    # dnat
  {%- if "nat" in pillar["ufw"] and "dnat" in pillar["ufw"]["nat"] and manage_nat %}
        dnat: |
    {%- for d_key, d_val in pillar["ufw"]["nat"]["dnat"].items()|sort %}
          # {{ d_key }}
      {%- if "from" in d_val %}
        {%- set src_block = "-s " ~ d_val["from"] %}
      {%- else %}
        {%- set src_block = " " %}
      {%- endif %}
      {%- if "daddr" in d_val %}
        {%- set daddr_block = "-d " ~ d_val["daddr"] %}
      {%- else %}
        {%- set daddr_block = " " %}
      {%- endif %}
      {%- if "in" in d_val %}
        {%- set in_block = "-i " ~ d_val["in"] %}
      {%- else %}
        {%- set in_block = " " %}
      {%- endif %}
          -A PREROUTING {{ in_block }} {{ src_block }} -p {{ d_val["proto"] }} {{ daddr_block }} --dport {{ d_val["dport"] }} -j DNAT --to-destination {{ d_val["to"] }}
    {%- endfor %}
  {%- else %}
        dnat: "# empty"
  {%- endif %}
    # snat
  {%- if "nat" in pillar["ufw"] and "snat" in pillar["ufw"]["nat"] and manage_nat %}
        snat: |
    {%- for s_key, s_val in pillar["ufw"]["nat"]["snat"].items()|sort %}
          # {{ s_key }}
      {%- if "from" in s_val %}
        {%- set src_block = "-s " ~ s_val["from"] %}
      {%- else %}
        {%- set src_block = " " %}
      {%- endif %}
          -A POSTROUTING -o {{ s_val["out"] }} {{ src_block }} -p {{ s_val["proto"] }} --dport {{ s_val["dport"] }} -j SNAT --to {{ s_val["to"] }}
    {%- endfor %}
  {%- else %}
        snat: "# empty"
  {%- endif %}
    # redirect
  {%- if "nat" in pillar["ufw"] and "redirect" in pillar["ufw"]["nat"] and manage_nat %}
        redirect: |
    {%- for r_key, r_val in pillar["ufw"]["nat"]["redirect"].items()|sort %}
          # {{ r_key }}
      {%- if "src" in r_val %}
        {%- set src_block = "--src " ~ r_val["src"] %}
      {%- else %}
        {%- set src_block = " " %}
      {%- endif %}
      {%- if "dst" in r_val %}
        {%- set dst_block = "--dst " ~ r_val["dst"] %}
      {%- else %}
        {%- set dst_block = " " %}
      {%- endif %}
          -A PREROUTING -i {{ r_val["in"] }} {{ src_block }} {{ dst_block }} -p {{ r_val["proto"] }} --dport {{ r_val["dport"] }} -j REDIRECT --to-ports {{ r_val["to_ports"] }}
    {%- endfor %}
  {%- else %}
        redirect: "# empty"
  {%- endif %}
    # custom_nat
  {%- if "custom" in pillar["ufw"] and "nat" in pillar["ufw"]["custom"] and manage_nat %}
        custom_nat: {{ pillar["ufw"]["custom"]["nat"] | yaml_encode }}
  {%- else %}
        custom_nat: "# empty"
  {%- endif %}
    # custom_filter
  {%- if "custom" in pillar["ufw"] and "filter" in pillar["ufw"]["custom"] %}
        custom_filter: {{ pillar["ufw"]["custom"]["filter"] | yaml_encode }}
  {%- else %}
        custom_filter: "# empty"
  {%- endif %}

  # Fill src rules with ufw commands to process next
ufw_user_rules_src_managed:
  file.managed:
    - name: /etc/ufw/user.rules.src
    - mode: 0640
    - contents: |
  {%- for rule_action in ["allow", "deny", "reject", "limit"] %}
    {%- if rule_action in pillar["ufw"] %}
      {%- for rule_name, rule_params in pillar["ufw"][rule_action].items() %}

        {%- if "insert" in rule_params %}
          {%- set rule_insert = "insert " ~ rule_params["insert"]|string %}
        {%- else %}
          {%- set rule_insert = "" %}
        {%- endif %}

        {%- if "from" in rule_params %}
          {%- set rule_from = rule_params["from"] %}
        {%- else %}
          {%- set rule_from = {"any": "any"} %}
        {%- endif %}

        {%- if "to" in rule_params %}
          {%- set rule_to = rule_params["to"] %}
        {%- else %}
          {%- set rule_to = {"any": "any"} %}
        {%- endif %}

        {%- if "proto" in rule_params %}
          {%- set rule_proto = "proto " ~ rule_params["proto"] %}
          {%- set rule_to_port = "port " ~ rule_params["to_port"] %}
        {%- else %}
          {%- set rule_proto = "" %}
          {%- set rule_to_port = "" %}
        {%- endif %}

        {%- if "direction" in rule_params %}
          {%- set rule_direction = " " ~ rule_params["direction"] ~ " " %}
        {%- else %}
          {%- set rule_direction = " " %}
        {%- endif %}

        {%- set i_loop = loop %}
        {%- for i_from in rule_from %}
          {%- set j_loop = loop %}
          {%- for i_to in rule_to %}
        ufw {{ rule_insert }} {{ rule_action }}{{ rule_direction }}{{ rule_proto }} from {{ rule_from[i_from] }} to {{ rule_to[i_to] }} {{ rule_to_port }} comment "{{ rule_name }} from {{ i_from }} to {{ i_to }}"
          {%- endfor %}
        {%- endfor %}
      {%- endfor %}
    {%- endif %}
  {%- endfor %}

  # Manage /etc/ufw/user.rules.py script
ufw_user_rules_py_managed:
  file.managed:
    - name: /etc/ufw/user.rules.py
  {%- if grains["osfinger"] == "CentOS Linux-7" %}
    - source: salt://ufw/files/etc_ufw_user.rules.py2
  {%- else %}
    - source: salt://ufw/files/etc_ufw_user.rules.py
  {%- endif %}
    - mode: 0700

  # Generate tmp user rules
ufw_user_rules_gen_tmp:
  cmd.run:
    - name: |
        /etc/ufw/user.rules.py v4 > /etc/ufw/user.rules.tmp

ufw_user6_rules_gen_tmp:
  cmd.run:
    - name: |
        # ufw adds those rules on each reload and file changes each time, add them not to change the file
        /etc/ufw/user.rules.py v6 \
          | sed -e 's/### RULES ###/:ufw6-user-limit - [0:0]\n:ufw6-user-limit-accept - [0:0]\n### RULES ###/' \
          | sed -e 's/COMMIT/\n### RATE LIMITING ###\n-A ufw6-user-limit -j REJECT\n-A ufw6-user-limit-accept -j ACCEPT\n### END RATE LIMITING ###\nCOMMIT/' \
          > /etc/ufw/user6.rules.tmp

  # Manage /etc/ufw/user.rules
ufw_user_rules_managed:
  file.managed:
  {%- if grains["os"] in ["CentOS"] %}
    - name: /var/lib/ufw/user.rules
  {%- else %}
    - name: /etc/ufw/user.rules
  {%- endif %}
    - source: /etc/ufw/user.rules.tmp
    - mode: 0640
    - keep_source: False
    - onlyif:
      - fun: file.file_exists
        path: /etc/ufw/user.rules.tmp

  # Manage /etc/ufw/user6.rules
ufw_user6_rules_managed:
  file.managed:
  {%- if grains["os"] in ["CentOS"] %}
    - name: /var/lib/ufw/user6.rules
  {%- else %}
    - name: /etc/ufw/user6.rules
  {%- endif %}
    - source: /etc/ufw/user6.rules.tmp
    - mode: 0640
    - keep_source: False
    - onlyif:
      - fun: file.file_exists
        path: /etc/ufw/user6.rules.tmp

  # Manage /etc/ufw/ufw.conf
ufw_conf_managed:
  file.managed:
    - name: /etc/ufw/ufw.conf
    - source: salt://ufw/files/etc_ufw_ufw.conf
    - mode: 0644
    - template: jinja
    - defaults:
        LOGLEVEL: {{ pillar["ufw"].get("loglevel", "'off'") }}

  # Reload ufw on any file change
ufw_reload:
  cmd.run:
    - name: "ufw --force reload"
    - onchanges:
      - file: /etc/ufw/ufw.conf
      - file: /etc/ufw/sysctl.conf
      - file: /etc/default/ufw
      - file: /etc/ufw/before.rules
  {%- if grains["os"] in ["CentOS"] %}
      - file: /var/lib/ufw/user.rules
      - file: /var/lib/ufw/user6.rules
  {%- else %}
      - file: /etc/ufw/user.rules
      - file: /etc/ufw/user6.rules
  {%- endif %}

  {% if "exec_after_apply" in pillar["ufw"] %}
exec_after:
  cmd.run:
    - name: {{ pillar["ufw"]["exec_after_apply"] }}
    - onchanges:
      - file: /etc/ufw/ufw.conf
      - file: /etc/ufw/sysctl.conf
      - file: /etc/default/ufw
      - file: /etc/ufw/before.rules
    {%- if grains["os"] in ["CentOS"] %}
      - file: /var/lib/ufw/user.rules
      - file: /var/lib/ufw/user6.rules
    {%- else %}
      - file: /etc/ufw/user.rules
      - file: /etc/ufw/user6.rules
    {%- endif %}
  {% endif %}

{% else %}
  {%- if pillar["_errors"] is defined %}
ufw_nothing_done_info:
  test.configurable_test_state:
    - name: nothing_done
    - changes: False
    - result: False
    - comment: |
        ERROR: There are pillar errors, so nothing has been done.
        {{ pillar["_errors"] | json() }}

  {%- else %}
ufw_nothing_done_info:
  test.configurable_test_state:
    - name: nothing_done
    - changes: False
    - result: True
    - comment: |
        INFO: This state was not configured with pillar, so nothing has been done. But it is OK.

  {%- endif %}
{% endif %}
