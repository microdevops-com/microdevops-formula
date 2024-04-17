{% from "./setup.sls" import logdir with context %}

{% if pillar["dante"] is defined and pillar["dante"]["config"]["simple"] %}


{% set simp_iface = pillar["dante"]["config"]["simple"]["interface"] %}
{% set simp_port  = pillar["dante"]["config"]["simple"]["port"]|default('15963') %}

Dante <> Config -> Simple:
  file.managed:
    - name: '/etc/danted.conf'
    - user: 'root'
    - group: 'root'
    - mode: '0644'
    - contents: |
        # Managed by Salt

        logoutput: {{ logdir }}/full.log
        errorlog: {{ logdir }}/error.log

        internal.protocol: ipv4
        internal: {{ simp_iface }} port = {{ simp_port }}
        external.protocol: ipv4 
        external: {{ simp_iface }}

        clientmethod: none
        socksmethod: none

        user.privileged: root
        user.notprivileged: nobody
        
        client pass {
          from: 0.0.0.0/0 to: 0.0.0.0/0
          log: error connect disconnect
        }
        client block {
          from: 0.0.0.0/0 to: 0.0.0.0/0
          log: connect error
        }
        socks pass {
          from: 0.0.0.0/0 to: 0.0.0.0/0
          log: error connect disconnect
        }
        socks block {
          from: 0.0.0.0/0 to: 0.0.0.0/0
          log: connect error
        }

Dante <> Reload service on config changes:
  service.running:
    - name: 'danted'
    - enable: True
    - watch:
      - file: '/etc/danted.conf'
          
{% endif %}
