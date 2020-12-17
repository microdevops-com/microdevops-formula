pkg:
  sentry-cli:
    when: PKG_PKG
    states:
      - cmd.run:
          1:
            - name: curl -L https://github.com/getsentry/sentry-cli/releases/download/1.61.0/sentry-cli-Linux-x86_64 -o /usr/local/bin/sentry-cli
          2:
            - name: chmod +x /usr/local/bin/sentry-cli
