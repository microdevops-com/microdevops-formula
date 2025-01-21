{% if pillar["nextcloud-aio"] is defined and pillar["acme"] is defined and pillar["docker-ce"] is defined %}
before_check:
 cmd.run:
    - name: docker exec --user=www-data nextcloud-aio-nextcloud bash -c "grep 'int \$refreshExpiresIn\|string \$refreshToken' /var/www/html/custom_apps/user_oidc/lib/Model/Token.php"
fix Token.php:
  cmd.run:
    - name: docker exec --user=www-data nextcloud-aio-nextcloud sed -i 's/private int $refreshExpiresIn/private ?int $refreshExpiresIn/g;s/private string $refreshToken/private ?string $refreshToken/g' /var/www/html/custom_apps/user_oidc/lib/Model/Token.php
after_check:
 cmd.run:
    - name: docker exec --user=www-data nextcloud-aio-nextcloud bash -c "grep 'int \$refreshExpiresIn\|string \$refreshToken' /var/www/html/custom_apps/user_oidc/lib/Model/Token.php"
{% endif %}
