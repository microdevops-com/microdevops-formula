# Content
[pillar.example](./pillar.example)  
[pillar.example.wordpress](./pillar.example.wordpress)  
[pillar.example.legacy](./pillar.example.legacy)  
[acme vhost.conf example](./files/static-generic-acme/vhost.conf)  

# acme.sh with webroot  
Create the acme pillar, with content like this  
```
acme:
  webroot:
    vars:
      TYPE: webroot
    args: "-w /var/www/.acme_webroot/"
    ca_server: letsencrypt
```

In vhost.conf, http listener add this location  
```
    location /.well-known/ {
        alias /var/www/.acme_webroot/.well-known/;
    }
```

To make it look like this:  
```
server {
    listen 80;
    server_name {{ domain }};
    location /.well-known/ {
        alias /var/www/.acme_webroot/.well-known/;
    }
    location / {
        return 301 https://{{ domain }}$request_uri;
    }
}
```

Set `link_sites-enabled` and `reload` in nginx section to True  
```
          link_sites-enabled: True
          reload: True
```
Optionally you can use `pillar='{nginx_reload: True}'`


And run `state.apply app.(php-fpm|static|python)`
