from sentry.conf.server import *

import os.path

CONF_ROOT = os.path.dirname(__file__)

DATABASES = {
    'default': {
        'ENGINE': 'sentry.db.postgres',
        'NAME': '{{ pg_db }}',
        'USER': '{{ pg_user }}',
        'PASSWORD': '{{ pg_pass }}',
        'HOST': '{{ pg_host }}',
        'PORT': '{{ pg_port }}',
        'AUTOCOMMIT': True,
        'ATOMIC_REQUESTS': False,
    }
}

SENTRY_USE_BIG_INTS = True

SENTRY_SINGLE_ORGANIZATION = True
DEBUG = False

SENTRY_CACHE = 'sentry.cache.redis.RedisCache'

BROKER_URL = 'redis://localhost:6379'

SENTRY_RATELIMITER = 'sentry.ratelimits.redis.RedisRateLimiter'

SENTRY_BUFFER = 'sentry.buffer.redis.RedisBuffer'

SENTRY_QUOTAS = 'sentry.quotas.redis.RedisQuota'

SENTRY_TSDB = 'sentry.tsdb.redis.RedisTSDB'

SENTRY_DIGESTS = 'sentry.digests.backends.redis.RedisBackend'

SENTRY_WEB_HOST = '0.0.0.0'
SENTRY_WEB_PORT = 9000
SENTRY_WEB_OPTIONS = {
    'workers': {{ workers }},
    'protocol': 'uwsgi',
}

SENTRY_FEATURES = {
    'auth:register': False,
    'projects:plugins': True,
}

INSTALLED_APPS += ('sentry_telegram',)

ALLOWED_HOSTS = [
    '*',
]

SECURE_PROXY_SSL_HEADER = ('HTTP_X_FORWARDED_PROTO', 'https')
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True
