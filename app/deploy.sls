include:
  - pkg.before_deploy
{% if (pillar['postgres'] is defined) and (pillar['postgres'] is not none) %}
  - postgres
{% endif %}
  - percona.percona
  - pyenv.pyenv
  - sentry.sentry
  - php-fpm.php-fpm
  - nginx.nginx
  - app.php-fpm_apps
  - app.static_apps
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
{% if (pillar['atlassian-jira'] is defined) and (pillar['atlassian-jira'] is not none) %}
  - atlassian-jira
{% endif %}
  - pkg.after_deploy
