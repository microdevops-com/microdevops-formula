pkg:
  erlang:
    when: 'PKG_BEFORE_DEPLOY'
    states:
      - pkg.installed:
          1:
            - sources:
              - erlang-solutions: 'salt://pkg/files/erlang-solutions_1.0_all.deb'
      - pkg.latest:
          1:
            - pkgs:
              - erlang-nox
