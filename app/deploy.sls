include:
  - sysctl
  - hosts
  - acme
  - pkg.before_deploy
{% if pillar["postgres"] is defined and pillar["postgres"] is not none %}
  {%- if pillar["postgres"]["client"] is defined and pillar["postgres"]["client"] %}
  - postgres.client
  {%- else %}
  - postgres
  {%- endif %}
{% endif %}
  - memcached
  - percona
  - rabbitmq
  - pyenv
  - rvm
  - php-fpm.php-fpm
  - nginx
  - app.php-fpm_apps
  - app.python_apps
  - app.static_apps
  - app.python
  - app.php-fpm
  - app.static
  - app.docker
  - pkg.after_deploy
  - proftpd.users
  - logrotate
