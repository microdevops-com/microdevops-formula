# CAUTION!  
Salt treats schedules with single word like `@reboot` or `@daily` differently from usual schedule like `* * * * *`.

So the cron entry created with the single word schedule:  
```
bootstrap:
  cron:
    root:
      present:
        restart_memcached:
          name: systemctl restart memcached
          schedule: "@daily"
```  

Can only be deleted or changed only with the single word schedule:  
```
bootstrap:
  cron:
    root:
      present:
        restart_memcached:
          name: sleep $RANDOM && systemctl restart memcached
          schedule: "@daily"
```  

Changing the schedule to default syntax like `00 00 * * *`, and applying the state will result in two cron entries,  
one with `@reboot` and another with `00 00 * * *`:  
```
bootstrap:
  cron:
    root:
      present:
        restart_memcached:
          name: sleep $RANDOM && systemctl restart memcached
          schedule: "00 00 * * *" # was schedule: "@daily"
```  

The result:  
```
# SALT_CRON_IDENTIFIER:restart_memcached
@reboot sleep $RANDOM && systemctl restart memcached
# SALT_CRON_IDENTIFIER:restart_memcached
00 00 * * * sleep $RANDOM && systemctl restart memcached
```

So please pay attention when using single word schedule syntax.  


# Data structure example:  


```
<some top level key>:
  cron:
    <user>: # user which crontab will be modified 
      present: # string, can be present, absent, env_present, env_absent
        <unique id>: # unique id for SALT_CRON_IDENTIFIER
          name:      # string, command to run
          schedule:  # string, cron's scheduling syntax, f.e. '* * * * *' or '@reboot'
          comment:   # string, optional comment string before SALT_CRON_IDENTIFIER
          disabled:  # bool, optional, default False, if true, cron command will be prefixed with #DISABLED# 
          user:      # string, optional, for usage in another states. Overrides the default user
  
      absent:
        <unique id>: # unique id for SALT_CRON_IDENTIFIER
          name:      # string, optional
          schedule:  # string, required to delete sindle word schedules like @reboot
  
      env_present:
        <ENV_VAR>:   # variable name
          value:     # string, required
  
      env_absent:
        <ENV_VAR>:   # variable name
```

# Usage example

```
<some top level key>:
  cron:
    root:
      present:
        clean_tmp_php:
          name: find /tmp/ -name "php*" -mtime +3  -delete
          schedule: '26 * * * *'
```

```
  {%- from "_include/cron_manager/macros.jinja" import cron_manager %}

  {{ cron_manager(<cron_data_dict>) }}
  OR
  {{ cron_manager(cron = <cron_data_dict>, prefix = "<custom_state_name_prefix>") }}
```
