# This file is just Python, with a touch of Django which means
# you can inherit and tweak settings to your hearts content.

from sentry.conf.server import *

import os.path

CONF_ROOT = {{ salt['pillar.get']('sentry:config:conf_root', 'os.path.dirname(__file__)') }}

DATABASES = {
    'default': {
        'ENGINE': '{{ salt['pillar.get']('sentry:config:db:engine', 'sentry.db.postgres') }}',
        'NAME': '{{ salt['pillar.get']('sentry:config:db:name', 'sentry') }}',
        'USER': '{{ salt['pillar.get']('sentry:config:db:user', 'postgres') }}',
        'PASSWORD': '{{ salt['pillar.get']('sentry:config:db:password', '') }}',
        'HOST': '{{ salt['pillar.get']('sentry:config:db:host', '') }}',
        'PORT': '{{ salt['pillar.get']('sentry:config:db:port', '') }}',
        'AUTOCOMMIT': {{ salt['pillar.get']('sentry:config:db:autocommit', 'True') }},
        'ATOMIC_REQUESTS': False,
    }
}
# You should not change this setting after your database has been created
# unless you have altered all schemas first
SENTRY_USE_BIG_INTS = {{ salt['pillar.get']('sentry:config:big_ints', 'True') }},

# If you're expecting any kind of real traffic on Sentry, we highly recommend
# configuring the CACHES and Redis settings

###########
# General #
###########

# Instruct Sentry that this install intends to be run by a single organization
# and thus various UI optimizations should be enabled.
SENTRY_SINGLE_ORGANIZATION = {{ salt['pillar.get']('sentry:config:single_organization', 'True') }}
DEBUG = {{ salt['pillar.get']('sentry:config:debug', 'False') }}

#########
# Cache #
#########

# Sentry currently utilizes two separate mechanisms. While CACHES is not a
# requirement, it will optimize several high throughput patterns.

# If you wish to use memcached, install the dependencies and adjust the config
# as shown:
#
#   pip install python-memcached
#
# CACHES = {
#     'default': {
#         'BACKEND': 'django.core.cache.backends.memcached.MemcachedCache',
#         'LOCATION': ['127.0.0.1:11211'],
#     }
# }

# A primary cache is required for things such as processing events
SENTRY_CACHE = '{{ salt['pillar.get']('sentry:config:cache', 'sentry.cache.redis.RedisCache') }}'

#########
# Queue #
#########

# See https://docs.sentry.io/on-premise/server/queue/ for more
# information on configuring your queue broker and workers. Sentry relies
# on a Python framework called Celery to manage queues.
BROKER_URL = '{{ salt['pillar.get']('sentry:config:broker_url', 'redis://localhost:6379') }}'

###############
# Rate Limits #
###############

# Rate limits apply to notification handlers and are enforced per-project
# automatically.
SENTRY_RATELIMITER = '{{ salt['pillar.get']('sentry:config:rate_limits', 'sentry.ratelimits.redis.RedisRateLimiter') }}'

##################
# Update Buffers #
##################

# Buffers (combined with queueing) act as an intermediate layer between the
# database and the storage API. They will greatly improve efficiency on large
# numbers of the same events being sent to the API in a short amount of time.
# (read: if you send any kind of real data to Sentry, you should enable buffers)
SENTRY_BUFFER = '{{ salt['pillar.get']('sentry:config:buffer', 'sentry.buffer.redis.RedisBuffer') }}'

##########
# Quotas #
##########

# Quotas allow you to rate limit individual projects or the Sentry install as
# a whole.

SENTRY_QUOTAS = '{{ salt['pillar.get']('sentry:config:quota', 'sentry.quotas.redis.RedisQuota') }}'

########
# TSDB #
########

# The TSDB is used for building charts as well as making things like per-rate
# alerts possible.

SENTRY_TSDB = '{{ salt['pillar.get']('sentry:config:tsdb', 'sentry.tsdb.redis.RedisTSDB') }}'

###########
# Digests #
###########

# The digest backend powers notification summaries.

SENTRY_DIGESTS = '{{ salt['pillar.get']('sentry:config:digests', 'sentry.digests.backends.redis.RedisBackend') }}'

##############
# Web Server #
##############

# If you're using a reverse SSL proxy, you should enable the X-Forwarded-Proto
# header and uncomment the following settings
{% if salt['pillar.get']('sentry:config:web:ssl', False) == True %}
SECURE_PROXY_SSL_HEADER = ('HTTP_X_FORWARDED_PROTO', 'https')
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True
{% endif %}


# If you're not hosting at the root of your web server,
# you need to uncomment and set it to the path where Sentry is hosted.
# FORCE_SCRIPT_NAME = '/sentry'

SENTRY_WEB_HOST = '{{ salt['pillar.get']('sentry:config:web:host', '0.0.0.0') }}'
SENTRY_WEB_PORT = {{ salt['pillar.get']('sentry:config:web:port', '9000') }}
SENTRY_WEB_OPTIONS = {
    'workers': {{ salt['pillar.get']('sentry:config:web:workers', '3') }},  # the number of web
    'protocol': '{{ salt['pillar.get']('sentry:config:web:protocol', 'uwsgi') }}',
}


SENTRY_FEATURES = {
    'auth:register': False,
    'projects:plugins': True,
}
