include:
  - pkg.before_deploy
  - postgresql.postgresql
  - percona.percona
  - pyenv.pyenv
  - sentry.sentry
  - php-fpm.php-fpm
  - nginx.nginx
  - app.php-fpm_apps
  - app.python_apps
{% if (pillar['java'] is defined) and (pillar['java'] is not none) %}
  - sun-java.opt_dir
  - sun-java
  - sun-java.env
{% endif %}
{% if (pillar['zookeeper'] is defined) and (pillar['zookeeper'] is not none) %}
  - zookeeper
  - zookeeper.config
  - zookeeper.server
{% endif %}
  - pkg.after_deploy
