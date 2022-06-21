include:
{% if pillar['sysctl'] is defined %}
  - sysctl
{% endif %}
{% if pillar['acme'] is defined %}
  - acme
{% endif %}
  - pkg.before_deploy
{% if pillar['postgres'] is defined and pillar['postgres'] is not none %}
  {%- if pillar['postgres']['client'] is defined and pillar['postgres']['client'] is not none and pillar['postgres']['client'] %}
  - postgres.client
  {%- else %}
  - postgres
  {%- endif %}
{% endif %}
  - memcached
  - percona
  - rabbitmq
  - pyenv
{% if pillar['sentry']['version'] is defined and pillar['sentry']['version'] is not none %}
  - sentry
{% endif %}
  - php-fpm.php-fpm
  - nginx
{% if pillar["app"] is defined and "php-fpm_apps" in pillar["app"] %}
  - app.php-fpm_apps
{% endif %}
{% if pillar["app"] is defined and "python_apps" in pillar["app"] %}
  - app.python_apps
{% endif %}
{% if pillar["app"] is defined and "static_apps" in pillar["app"] %}
  - app.static_apps
{% endif %}
{% if pillar["app"] is defined and "python" in pillar["app"] %}
  - app.python
{% endif %}
{% if pillar["app"] is defined and "php-fpm" in pillar["app"] %}
  - app.php-fpm
{% endif %}
{% if pillar["app"] is defined and "static" in pillar["app"] %}
  - app.static
{% endif %}
  - app.docker
{% if pillar['java'] is defined and pillar['java'] is not none %}
  - sun-java.opt_dir
  - sun-java
  - sun-java.env
{% endif %}
{% if pillar['zookeeper'] is defined and pillar['zookeeper'] is not none %}
  - zookeeper
  - zookeeper.config
  - zookeeper.server
{% endif %}
{% if pillar['atlassian-jira'] is defined and pillar['atlassian-jira'] is not none %}
  - atlassian-jira
{% endif %}
{% if pillar['atlassian-confluence'] is defined and pillar['atlassian-confluence'] is not none %}
  - atlassian-confluence
{% endif %}
  - pkg.after_deploy
  - proftpd.users
{% if pillar['logrotate'] is defined %}
  - logrotate
{% endif %}
