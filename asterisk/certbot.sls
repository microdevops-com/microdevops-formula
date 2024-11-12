{% if pillar["asterisk"] is defined and "certbot" in pillar["asterisk"] %}

{% if pillar["asterisk"]["certbot"] is defined and "dns-cloudflare" in pillar["asterisk"]["certbot"] %}
{% set domain = pillar["asterisk"]["certbot"]["dns-cloudflare"]["domain"] %}
{% set dns_cloudflare_api_token = pillar["asterisk"]["certbot"]["dns-cloudflare"]["dns_cloudflare_api_token"] %}

certbot-dns-cloudflare:
  pip.installed:
    - reload_modules: True
    - names:
      - certbot-dns-cloudflare

create-dir-secrets:
  file.directory:
    - name: /root/.secrets
    - user: root
    - group: root
    - dir_mode: 700

create-dir-asterisk-keys:
  file.directory:
    - name: /etc/asterisk/keys
    - user: asterisk
    - group: asterisk
    - dir_mode: 755


certbot-dns-cloudflare-cron:
  cron.present:
    - identifier: certbot renew certificates
    - name: /usr/local/bin/certbot -q renew ; /usr/sbin/asterisk -rx "core reload"
    - user: root
    - minute: 5
    - hour: 10
    - dayweek: 6

create_token_file_cf:
  file.managed:
    - name: /root/.secrets/cf_{{ domain }}.ini
    - user: root
    - group: root
    - mode: 600
    - contents: |
        # {{ domain }}
        dns_cloudflare_api_token = {{ dns_cloudflare_api_token }}
    - require:
      - file: "/root/.secrets"

create_certificate:
  cmd.run:
    - name: certbot certonly --non-interactive --cert-name {{ domain }} --agree-tos -m le-report@oxtech.org --dns-cloudflare --dns-cloudflare-credentials /root/.secrets/cf_{{ domain }}.ini --dns-cloudflare-propagation-seconds 60 --preferred-challenges dns-01 -d {{ domain }} -d *.{{ domain }}
    - runas: root
    - require:
      - pip: "certbot-dns-cloudflare"

create_symlink_cert_asterisk:
    cmd.run:
      - name: ln -sf /etc/letsencrypt/live/{{ domain }}/cert.pem /etc/asterisk/keys/asterisk.crt
      - runas: 'asterisk'
      - require:
        - cmd: certbot certonly --non-interactive --cert-name {{ domain }} --agree-tos -m le-report@oxtech.org --dns-cloudflare --dns-cloudflare-credentials /root/.secrets/cf_{{ domain }}.ini --dns-cloudflare-propagation-seconds 60 --preferred-challenges dns-01 -d {{ domain }} -d *.{{ domain }}

create_symlink_key_asterisk:
    cmd.run:
      - name: ln -sf /etc/letsencrypt/live/{{ domain }}/privkey.pem /etc/asterisk/keys/asterisk.key
      - runas: 'asterisk'
      - require:
        - cmd: certbot certonly --non-interactive --cert-name {{ domain }} --agree-tos -m le-report@oxtech.org --dns-cloudflare --dns-cloudflare-credentials /root/.secrets/cf_{{ domain }}.ini --dns-cloudflare-propagation-seconds 60 --preferred-challenges dns-01 -d {{ domain }} -d *.{{ domain }}
{% endif %}
{% endif %}