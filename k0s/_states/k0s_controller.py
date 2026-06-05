import os
import shlex


__virtualname__ = 'k0s_controller'

DEFAULT_BINARY = '/usr/local/bin/k0s'
DEFAULT_UNIT_PATH = '/etc/systemd/system/k0scontroller.service'


def __virtual__():
    return __virtualname__


def installed(
    name,
    config,
    data_dir,
    binary=DEFAULT_BINARY,
    unit_path=DEFAULT_UNIT_PATH,
    single=False,
    enable_worker=False,
    no_taints=False,
    extra_args=None,
):
    '''
    Install the k0s controller systemd unit with k0s install controller.
    '''
    ret = {
        'name': name,
        'changes': {},
        'result': True,
        'comment': '',
    }

    extra_args_result = _normalize_extra_args(extra_args)
    if not extra_args_result['result']:
        ret['result'] = False
        ret['comment'] = extra_args_result['comment']
        return ret

    extra_argv = extra_args_result['args']
    install_command = _install_command(
        binary=binary,
        config=config,
        data_dir=data_dir,
        single=single,
        enable_worker=enable_worker,
        no_taints=no_taints,
        extra_args=extra_argv,
        force=False,
    )
    desired_args = _desired_unit_args(
        config=config,
        data_dir=data_dir,
        single=single,
        enable_worker=enable_worker,
        no_taints=no_taints,
        extra_args=extra_argv,
    )

    missing = _missing_prerequisites(binary, config)
    if missing:
        ret['result'] = False
        ret['comment'] = 'Missing required file(s): {0}.'.format(', '.join(missing))
        return ret

    if not _systemd_available():
        ret['result'] = False
        ret['comment'] = 'systemd is required to install {0}.'.format(unit_path)
        return ret

    initial_unit_status = _unit_status(unit_path, desired_args)
    if initial_unit_status['result']:
        ret['comment'] = 'k0s controller unit is already installed with the requested arguments.'
        return ret

    if initial_unit_status['previous'] != 'missing':
        install_command = _install_command(
            binary=binary,
            config=config,
            data_dir=data_dir,
            single=single,
            enable_worker=enable_worker,
            no_taints=no_taints,
            extra_args=extra_argv,
            force=True,
        )

    if __opts__.get('test'):
        ret['result'] = None
        ret['changes'] = {'unit': {'old': initial_unit_status['comment'], 'new': 'installed'}}
        ret['comment'] = 'k0s controller unit would be installed with: {0}'.format(
            ' '.join(shlex.quote(part) for part in install_command)
        )
        return ret

    result = __salt__['cmd.run_all'](install_command, python_shell=False)
    if result.get('retcode') != 0:
        ret['result'] = False
        ret['comment'] = _command_failure_comment(result)
        return ret

    unit_status = _unit_status(unit_path, desired_args)
    if not unit_status['result']:
        ret['result'] = False
        ret['comment'] = (
            'k0s install controller completed, but the unit does not match the '
            'requested arguments: {0}.'.format(unit_status['comment'])
        )
        return ret

    ret['changes'] = {'unit': {'old': initial_unit_status['previous'], 'new': unit_path}}
    ret['comment'] = 'k0s controller unit was installed.'
    return ret


def _normalize_extra_args(extra_args):
    if extra_args is None or extra_args == '':
        return {'result': True, 'args': []}

    if isinstance(extra_args, list):
        return {'result': True, 'args': [str(arg) for arg in extra_args]}

    if not isinstance(extra_args, str):
        return {
            'result': False,
            'comment': 'extra_args must be a string or a list.',
        }

    try:
        return {'result': True, 'args': shlex.split(extra_args)}
    except ValueError as exc:
        return {
            'result': False,
            'comment': 'Unable to parse extra_args: {0}.'.format(exc),
        }


def _install_command(binary, config, data_dir, single, enable_worker, no_taints, extra_args, force):
    command = [binary, 'install']

    if force:
        command.append('--force')

    command.extend([
        'controller',
        '--config',
        config,
        '--data-dir',
        data_dir,
    ])

    if single:
        command.append('--single')

    if enable_worker:
        command.append('--enable-worker')

    if no_taints:
        command.append('--no-taints')

    command.extend(extra_args)
    return command


def _desired_unit_args(config, data_dir, single, enable_worker, no_taints, extra_args):
    args = [
        ('option', '--config', config),
        ('option', '--data-dir', data_dir),
    ]

    if single:
        args.append(('flag', '--single', None))

    if enable_worker:
        args.append(('flag', '--enable-worker', None))

    if no_taints:
        args.append(('flag', '--no-taints', None))

    for arg in extra_args:
        args.append(('token', arg, None))

    return args


def _missing_prerequisites(binary, config):
    missing = []

    if not os.path.isfile(binary) or not os.access(binary, os.X_OK):
        missing.append(binary)

    if not os.path.isfile(config):
        missing.append(config)

    return missing


def _systemd_available():
    return os.path.isdir('/run/systemd/system') and os.path.exists('/bin/systemctl')


def _unit_status(unit_path, desired_args):
    if not os.path.isfile(unit_path):
        return {
            'result': False,
            'comment': '{0} is missing'.format(unit_path),
            'previous': 'missing',
        }

    with open(unit_path) as unit_file:
        unit_content = unit_file.read()

    exec_args = _exec_start_args(unit_content)
    if not exec_args:
        return {
            'result': False,
            'comment': 'ExecStart is missing',
            'previous': unit_path,
        }

    missing_args = _missing_unit_args(exec_args, desired_args)
    if missing_args:
        return {
            'result': False,
            'comment': 'missing argument(s): {0}'.format(', '.join(missing_args)),
            'previous': unit_path,
        }

    return {
        'result': True,
        'comment': 'unit matches requested arguments',
        'previous': unit_path,
    }


def _exec_start_args(unit_content):
    for line in unit_content.splitlines():
        line = line.strip()
        if not line.startswith('ExecStart='):
            continue

        command = line.split('=', 1)[1]
        try:
            return shlex.split(command)
        except ValueError:
            return command.split()

    return []


def _missing_unit_args(exec_args, desired_args):
    missing = []

    for kind, option, value in desired_args:
        if kind == 'option' and not _has_option(exec_args, option, value):
            missing.append('{0} {1}'.format(option, value))
        elif kind == 'flag' and not _has_flag(exec_args, option):
            missing.append(option)
        elif kind == 'token' and option not in exec_args:
            missing.append(option)

    return missing


def _has_option(args, option, value):
    if '{0}={1}'.format(option, value) in args:
        return True

    for index, arg in enumerate(args):
        if arg == option and index + 1 < len(args) and args[index + 1] == value:
            return True

    return False


def _has_flag(args, option):
    return option in args or '{0}=true'.format(option) in args


def _command_failure_comment(result):
    output = result.get('stderr') or result.get('stdout') or 'no output'
    return 'k0s install controller failed with exit code {0}: {1}'.format(
        result.get('retcode'),
        output.strip(),
    )
