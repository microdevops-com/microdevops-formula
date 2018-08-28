pkg:
  r:
    when: 'PKG_BEFORE_DEPLOY'
    states:
      - pkgrepo.managed:
          1:
            - humanname: R Studio Repository
            - name: deb http://cran.rstudio.com/bin/linux/ubuntu {{ grains['oscodename'] }}/
            - file: /etc/apt/sources.list.d/rstudio.list
            - keyserver: keyserver.ubuntu.com
            - keyid: E084DAB9
            - refresh_db: true
      - pkg.latest:
          1:
            - pkgs:
                - r-base
