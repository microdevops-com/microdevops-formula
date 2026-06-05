import os


__virtualname__ = 'k0s_manifest'

DEFAULT_BINARY = '/usr/local/bin/k0s'


def __virtual__():
    return __virtualname__


def applied(name, binary=DEFAULT_BINARY, source=None, content=None):
    '''
    Apply Kubernetes manifests via k0s kubectl apply.

    At least one of source or content must be provided. Both may be given
    simultaneously — their YAML documents are concatenated before applying.

    name
        Arbitrary identifier used as the state name.

    binary
        Path to the k0s binary. Defaults to /usr/local/bin/k0s.

    source
        Path to a manifest file on the local filesystem.

    content
        Inline YAML manifest string.
    '''
    ret = {
        'name': name,
        'changes': {},
        'result': True,
        'comment': '',
    }

    if source is None and content is None:
        ret['result'] = False
        ret['comment'] = 'At least one of source or content must be provided.'
        return ret

    if content is not None and not isinstance(content, str):
        ret['result'] = False
        ret['comment'] = 'content must be a string.'
        return ret

    if not os.path.isfile(binary) or not os.access(binary, os.X_OK):
        ret['result'] = False
        ret['comment'] = 'Missing required file: {0}.'.format(binary)
        return ret

    manifest_parts = []

    if source is not None:
        source_result = _read_source(source)
        if not source_result['result']:
            ret['result'] = False
            ret['comment'] = source_result['comment']
            return ret
        manifest_parts.append(source_result['content'])

    if content is not None:
        manifest_parts.append(content)

    combined = '\n---\n'.join(manifest_parts)
    command = [binary, 'kubectl', 'apply', '-f', '-']

    if __opts__.get('test'):
        ret['result'] = None
        ret['changes'] = {'manifests': {'old': 'unknown', 'new': 'applied'}}
        ret['comment'] = 'Manifests would be applied with: {0}'.format(' '.join(command))
        return ret

    result = __salt__['cmd.run_all'](
        command,
        python_shell=False,
        stdin=combined,
    )

    if result.get('retcode') != 0:
        ret['result'] = False
        ret['comment'] = _command_failure_comment(result)
        return ret

    stdout = result.get('stdout', '')
    changes = _parse_changes(stdout)

    if changes:
        ret['changes'] = {'manifests': changes}
        ret['comment'] = 'Manifests were applied.'
    else:
        ret['comment'] = 'Manifests are already up to date.'

    return ret


def _read_source(source):
    if not os.path.isfile(source):
        return {
            'result': False,
            'comment': 'Source file not found: {0}.'.format(source),
        }

    try:
        with open(source, 'r') as manifest_file:
            return {'result': True, 'content': manifest_file.read()}
    except OSError as exc:
        return {
            'result': False,
            'comment': 'Unable to read source file {0}: {1}.'.format(source, exc),
        }


def _parse_changes(output):
    created = []
    configured = []

    for line in output.splitlines():
        line = line.strip()
        if line.endswith(' created'):
            created.append(line[: -len(' created')])
        elif line.endswith(' configured'):
            configured.append(line[: -len(' configured')])

    changes = {}
    if created:
        changes['created'] = created
    if configured:
        changes['configured'] = configured

    return changes


def _command_failure_comment(result):
    output = result.get('stderr') or result.get('stdout') or 'no output'
    return 'k0s kubectl apply failed with exit code {0}: {1}'.format(
        result.get('retcode'),
        output.strip(),
    )