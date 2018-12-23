pkg:
  rabbitmqadmin:
    when: 'PKG_BEFORE_DEPLOY'
    states:
      - cmd.run:
          1:
            - name: 'curl -L https://raw.githubusercontent.com/rabbitmq/rabbitmq-management/v3.7.9/bin/rabbitmqadmin -o /usr/local/bin/rabbitmqadmin'
          2:
            - name: 'chmod +x /usr/local/bin/rabbitmqadmin'
