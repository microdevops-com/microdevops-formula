{%- if grains["os"] not in ["CentOS"] %}
history_skel_bashrc:
  file.line:
    - name: '/etc/skel/.bashrc'
    - mode: ensure
    - after: ".*HISTSIZE and HISTFILESIZE.*"
    - content: "export HISTTIMEFORMAT='%Y-%m-%d %H:%M:%S '"
{%- endif %}

ps1_skel_bashrc_1:
  file.replace:
    - name: '/etc/skel/.bashrc'
    - pattern: '\\h'
    - repl: '\\H'

ps1_skel_bashrc_2:
  file.replace:
    - name: '/etc/skel/.bashrc'
    - pattern: ']\\u'
    - repl: ']\\t bg:\\j \\u'

ps1_skel_bashrc_3:
  file.replace:
    - name: '/etc/skel/.bashrc'
    - pattern: '}\\u'
    - repl: '}\\t bg:\\j \\u'

aliases_bashrc_1:
  file.uncomment:
    - name: '/etc/skel/.bashrc'
    - regex: '\[ -x /usr/bin/lesspipe'

{%- if grains["os"] not in ["CentOS"] %}
aliases_bashrc_2:
  file.uncomment:
    - name: '/etc/skel/.bashrc'
    - char: '    #'
    - regex: 'alias grep'

aliases_bashrc_3:
  file.uncomment:
    - name: '/etc/skel/.bashrc'
    - char: '    #'
    - regex: 'alias fgrep'

aliases_bashrc_4:
  file.uncomment:
    - name: '/etc/skel/.bashrc'
    - char: '    #'
    - regex: 'alias egrep'

aliases_bashrc_5:
  file.uncomment:
    - name: '/etc/skel/.bashrc'
    - regex: 'alias ll'

aliases_bashrc_6:
  file.uncomment:
    - name: '/etc/skel/.bashrc'
    - regex: 'alias la'

aliases_bashrc_7:
  file.uncomment:
    - name: '/etc/skel/.bashrc'
    - regex: 'alias l='
{%- endif %}

ps1_touch_byobu_bashrc:
  file.touch:
    - name: /usr/share/byobu/profiles/bashrc

ps1_share_byobu_bashrc_1:
  file.replace:
    - name: '/usr/share/byobu/profiles/bashrc'
    - pattern: '\\h'
    - repl: '\\H'

ps1_share_byobu_bashrc_2:
  file.replace:
    - name: '/usr/share/byobu/profiles/bashrc'
    - pattern: ']\\u'
    - repl: ']\\t bg:\\j \\u'

byobu_prompt_skel_bashrc:
  file.append:
    - name: '/etc/skel/.bashrc'
    - text: |
        [ ${_byobu_sourced}_ = 1_ ] && export TERM=tmux
        [ -r /usr/share/byobu/profiles/bashrc ] && . /usr/share/byobu/profiles/bashrc  #byobu-prompt#

bash_skel_system_root_bashrc:
  file.managed:
    - name: /root/.bashrc
    - source: /etc/skel/.bashrc
