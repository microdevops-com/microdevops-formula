import os


__virtualname__ = 'k0s_config'

DEFAULT_BINARY = '/usr/local/bin/k0s'


def __virtual__():
    return __virtualname__


def created(name, binary=DEFAULT_BINARY):
    '''
    Create a default k0s configuration file with k0s config create.
    '''
    ret = {
        'name': name,
        'changes': {},
        'result': True,
        'comment': '',
    }

    if os.path.exists(name):
        ret['comment'] = 'k0s configuration file already exists.'
        return ret

    missing = _missing_prerequisites(binary, name)
    if missing:
        ret['result'] = False
        ret['comment'] = 'Missing required path(s): {0}.'.format(', '.join(missing))
        return ret

    command = [binary, 'config', 'create']
    if __opts__.get('test'):
        ret['result'] = None
        ret['changes'] = {'config': {'old': 'missing', 'new': name}}
        ret['comment'] = 'k0s configuration file would be created with: {0}'.format(
            ' '.join(command)
        )
        return ret

    result = __salt__['cmd.run_all'](command, python_shell=False)
    if result.get('retcode') != 0:
        ret['result'] = False
        ret['comment'] = _command_failure_comment(result)
        return ret

    _write_file(name, result.get('stdout', ''))

    ret['changes'] = {'config': {'old': 'missing', 'new': name}}
    ret['comment'] = 'k0s configuration file was created.'
    return ret


def _missing_prerequisites(binary, path):
    missing = []

    if not os.path.isfile(binary) or not os.access(binary, os.X_OK):
        missing.append(binary)

    parent = os.path.dirname(path) or '.'
    if not os.path.isdir(parent):
        missing.append(parent)

    return missing


def _write_file(path, content):
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, 'w') as config_file:
        config_file.write(content)


def _command_failure_comment(result):
    output = result.get('stderr') or result.get('stdout') or 'no output'
    return 'k0s config create failed with exit code {0}: {1}'.format(
        result.get('retcode'),
        output.strip(),
    )
