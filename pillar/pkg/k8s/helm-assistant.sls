pkg:
  helm-assistant:
    when: PKG_BEFORE_DEPLOY
    states:
      - cmd.run:
          1:
            - name: curl -L https://github.com/SomeBlackMagic/helm-assistant/releases/download/v0.2.2/helm-assistant-linux-amd64 -o /usr/local/bin/helm-assistant
          2:
            - name: chmod +x /usr/local/bin/helm-assistant
