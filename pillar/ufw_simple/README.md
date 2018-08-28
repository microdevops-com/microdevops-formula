# Many pillars include /srv/pillar/ufw_simple/vars.jinja file and suppose that you have set vars array:
- ```vars['Office_And_VPN']```
- ```vars['Delete_Office_And_VPN']```
- ```vars['Backup_Servers']```
- ```vars['Delete_Backup_Servers']```
- ```vars['All_Servers']```
- ```vars['Delete_All_Servers']```

# Subarrays meaning:
- Office_And_VPN - is a list of IP with names for which to open SSH, for example.
- Backup_Servers - is a list of IP with names of backup servers, also SSH usually.
- All_Servers - is a list of IP with names of all servers in your control. E.g. to open 4505, 4506 from the minions to the master.
- Delete_* - the same list but marked for deletion.

# Sample file:

```
cat /srv/pillar/ufw_simple/vars.jinja
{%
set vars = {
  'Office_And_VPN': {
    'Office IP': '1.2.3.4',
    'VPN IP': '4.3.2.1'
  },
  'Delete_Office_And_VPN': {
  }
  'Backup_Servers': {
    'backup1.example.com': '1.2.3.4'
  }
  'Delete_Backup_Servers': {
  }
  'All_Servers': {
    'backup1.example.com': '1.2.3.4',
    'web1.example.com': '1.2.3.5',
    'minion1.example.com': '1.2.3.6',
    'master1.example.com': '1.2.3.6'
  }
  'Delete_All_Servers': {
    'alien1.example.com': '1.2.3.4'
  }
%}
```
