history_skel_bashrc:
  file.line:
    - name: '/etc/skel/.bashrc'
    - mode: ensure
    - after: ".*HISTSIZE and HISTFILESIZE.*"
    - content: "export HISTTIMEFORMAT='%Y-%m-%d %H:%M:%S '"

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
        [ ${_byobu_sourced}_ = 1_ ] && export TERM=screen-256color-bce
        [ -r /usr/share/byobu/profiles/bashrc ] && . /usr/share/byobu/profiles/bashrc  #byobu-prompt#

bash_skel_system_root_bashrc:
  file.managed:
    - name: /root/.bashrc
    - source: /etc/skel/.bashrc

{% for name, user in pillar.get('users', {}).items() if user.absent is not defined or not user.absent %}
  {%- set current = salt.user.info(name) -%}
  {%- if user == None -%}
    {%- set user = {} -%}
  {%- endif -%}
  {%- if
         (pillar['users'] is defined) and (pillar['users'] is not none) and
         (pillar['users'][name] is defined) and (pillar['users'][name] is not none) and
         (pillar['users'][name]['skip_bashrc'] is defined) and (pillar['users'][name]['skip_bashrc'] is not none) and
         (pillar['users'][name]['skip_bashrc'])
  %}
  {%- else %}
    {%- set home = user.get('home', current.get('home', "/home/%s" % name)) -%}
bash_skel_{{ name }}_bashrc:
  file.managed:
    - name: {{ home }}/.bashrc
    - user: {{ name }}
    - group: {{ name }}
    - source: /etc/skel/.bashrc
  {%- endif %}
{% endfor %}

byobu_fn_keys:
  file.append:
    - name: '/usr/share/byobu/keybindings/common'
    - text: "source $BYOBU_PREFIX/share/byobu/keybindings/f-keys.screen.disable # final"
