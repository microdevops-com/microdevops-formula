import os
import time


__virtualname__ = 'k0s_token'

DEFAULT_BINARY = '/usr/local/bin/k0s'


def __virtual__():
    return __virtualname__


def created(name, ttl=24, role='worker', binary=DEFAULT_BINARY):
    '''
    Create a k0s join token file.
    '''
    ret = {
        'name': name,
        'changes': {},
        'result': True,
        'comment': '',
    }

    ttl_result = _normalize_ttl(ttl)
    if not ttl_result['result']:
        ret['result'] = False
        ret['comment'] = ttl_result['comment']
        return ret

    ttl_hours = ttl_result['ttl']
    token_status = _token_status(name, ttl_hours)
    if token_status['current']:
        ret['comment'] = 'k0s {0} token file is current.'.format(role)
        return ret

    missing = _missing_prerequisites(binary, name)
    if missing:
        ret['result'] = False
        ret['comment'] = 'Missing required path(s): {0}.'.format(', '.join(missing))
        return ret

    command = [binary, 'token', 'create', '--role', role]
    if __opts__.get('test'):
        ret['result'] = None
        ret['changes'] = {'token': {'old': token_status['previous'], 'new': 'created'}}
        ret['comment'] = 'k0s {0} token file would be created with: {1}'.format(
            role,
            ' '.join(command),
        )
        return ret

    result = __salt__['cmd.run_all'](command, python_shell=False)
    if result.get('retcode') != 0:
        ret['result'] = False
        ret['comment'] = _command_failure_comment(result)
        return ret

    token = result.get('stdout', '').strip()
    if not token:
        ret['result'] = False
        ret['comment'] = 'k0s token create returned an empty token.'
        return ret

    _write_file(name, token + '\n')

    ret['changes'] = {'token': {'old': token_status['previous'], 'new': 'created'}}
    ret['comment'] = 'k0s {0} token file was created.'.format(role)
    return ret


def _normalize_ttl(ttl):
    try:
        ttl_hours = int(ttl)
    except (TypeError, ValueError):
        return {
            'result': False,
            'comment': 'ttl must be an integer number of hours.',
        }

    if ttl_hours < 0:
        return {
            'result': False,
            'comment': 'ttl must be greater than or equal to 0.',
        }

    return {'result': True, 'ttl': ttl_hours}


def _token_status(path, ttl_hours):
    if not os.path.exists(path):
        return {'current': False, 'previous': 'missing'}

    if not os.path.isfile(path):
        return {'current': False, 'previous': 'not a regular file'}

    if os.path.getsize(path) == 0:
        return {'current': False, 'previous': 'empty'}

    if ttl_hours == 0:
        return {'current': True, 'previous': path}

    age_seconds = time.time() - os.path.getmtime(path)
    if age_seconds < ttl_hours * 60 * 60:
        return {'current': True, 'previous': path}

    return {'current': False, 'previous': 'expired'}


def _missing_prerequisites(binary, path):
    missing = []

    if not os.path.isfile(binary) or not os.access(binary, os.X_OK):
        missing.append(binary)

    parent = os.path.dirname(path) or '.'
    if not os.path.isdir(parent):
        missing.append(parent)

    return missing


def _write_file(path, content):
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, 'w') as token_file:
        token_file.write(content)
    os.chmod(path, 0o600)


def _command_failure_comment(result):
    output = result.get('stderr') or result.get('stdout') or 'no output'
    return 'k0s token create failed with exit code {0}: {1}'.format(
        result.get('retcode'),
        output.strip(),
    )
