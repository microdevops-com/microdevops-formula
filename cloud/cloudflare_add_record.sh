#!/bin/bash
if [[ -f /srv/salt/cloud/cloudflare_add_record.conf ]]; then
        . /srv/salt/cloud/cloudflare_add_record.conf
	curl -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE/dns_records" \
	     -H "X-Auth-Email: $CF_EMAIL" \
	     -H "X-Auth-Key: $CF_KEY" \
	     -H "Content-Type: application/json" \
	     --data '{"type":"A","name":"'$1'","content":"'$2'","ttl":120,"proxied":false}'
	echo
else
	echo "No /srv/salt/cloud/cloudflare_add_record.conf config found."
	echo
fi
