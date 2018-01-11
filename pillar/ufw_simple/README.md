Many pillars include /srv/pillar/ufw_simple/vars.jinja file and suppose that you have local vars['Office_And_VPN'], vars['Backup_Servers'].
For example:

```
cat /srv/pillar/ufw_simple/vars.jinja
{%
set vars = {
  'Office_And_VPN': {
    'Office IP': '1.2.3.4',
    'VPN IP': '4.3.2.1'
  },
  'Backup_Servers': {
    'backup1.example.com': '1.2.3.4'
  }
%}
```
