import os
import time


__virtualname__ = 'k0s_cluster'

DEFAULT_BINARY = '/usr/local/bin/k0s'


def __virtual__():
    return __virtualname__


def operational(name, binary=DEFAULT_BINARY, timeout=120, interval=5):
    '''
    Wait until the k0s cluster answers kubectl get nodes.
    '''
    ret = {
        'name': name,
        'changes': {},
        'result': True,
        'comment': '',
    }

    timeout_result = _normalize_non_negative_int(timeout, 'timeout')
    if not timeout_result['result']:
        ret['result'] = False
        ret['comment'] = timeout_result['comment']
        return ret

    interval_result = _normalize_non_negative_int(interval, 'interval')
    if not interval_result['result']:
        ret['result'] = False
        ret['comment'] = interval_result['comment']
        return ret

    timeout = timeout_result['value']
    interval = interval_result['value']

    if not os.path.isfile(binary) or not os.access(binary, os.X_OK):
        ret['result'] = False
        ret['comment'] = 'Missing required file: {0}.'.format(binary)
        return ret

    check = _kubectl_get_nodes(binary)
    if check['result']:
        ret['comment'] = 'k0s cluster is operational.'
        return ret

    if __opts__.get('test'):
        ret['result'] = None
        ret['changes'] = {'cluster': {'old': 'not operational', 'new': 'operational'}}
        ret['comment'] = 'k0s cluster would be checked until kubectl get nodes succeeds.'
        return ret

    deadline = time.time() + timeout
    while time.time() < deadline:
        if interval:
            time.sleep(interval)

        check = _kubectl_get_nodes(binary)
        if check['result']:
            ret['changes'] = {'cluster': {'old': 'not operational', 'new': 'operational'}}
            ret['comment'] = 'k0s cluster became operational.'
            return ret

    ret['result'] = False
    ret['comment'] = _command_failure_comment(check)
    return ret


def _kubectl_get_nodes(binary):
    result = __salt__['cmd.run_all'](
        [binary, 'kubectl', 'get', 'nodes'],
        python_shell=False,
    )
    return {
        'result': result.get('retcode') == 0,
        'raw': result,
    }


def _normalize_non_negative_int(value, name):
    try:
        normalized = int(value)
    except (TypeError, ValueError):
        return {
            'result': False,
            'comment': '{0} must be an integer.'.format(name),
        }

    if normalized < 0:
        return {
            'result': False,
            'comment': '{0} must be greater than or equal to 0.'.format(name),
        }

    return {'result': True, 'value': normalized}


def _command_failure_comment(check):
    result = check['raw']
    output = result.get('stderr') or result.get('stdout') or 'no output'
    return 'k0s cluster did not become operational: {0}'.format(output.strip())
