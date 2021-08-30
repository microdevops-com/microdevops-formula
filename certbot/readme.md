# state: certbot
## info
This is certbot - in - venv state. Intended for use with legacy `app` states.  
e.g. with `pillar='{ certbot_run_ready: True }'`

State runs only when `certbot: True` is set in app pillar:
```yaml
app:
  php-fpm_apps|python_apps|static_apps:
    app_1:
      ...
      nginx:
        ...
        ssl:
          certbot: True
```
