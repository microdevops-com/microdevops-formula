pkg:
  memcached:
    when: 'PKG_BEFORE_DEPLOY'
    states:
      - pkg.installed:
          1:
            - pkgs:
                - memcached
