pkg:
  supervisor:
    when: 'PKG_BEFORE_DEPLOY'
    states:
      - pkg.installed:
          1:
            - pkgs:
                - supervisor
