include:
  - pkg.before_deploy
  - proftpd.users
{% if pillar['postgres'] is defined and pillar['postgres'] is not none %}
  {%- if pillar['postgres']['client'] is defined and pillar['postgres']['client'] is not none and pillar['postgres']['client'] %}
  - postgres.client
  {%- else %}
  - postgres
  {%- endif %}
{% endif %}
  - percona.percona
  - rabbitmq.rabbitmq
  - pyenv.pyenv
{% if pillar['sentry'] is defined and pillar['sentry'] is not none %}
  - sentry.sentry
{% endif %}
  - php-fpm.php-fpm
  - nginx.nginx
  - app.php-fpm_apps
  - app.static_apps
  - app.python_apps
  - app.python
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
