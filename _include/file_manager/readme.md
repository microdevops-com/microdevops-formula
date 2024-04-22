# File manager
The file manager state, pillar data example is listed below.  
The states are applied in the following order: recurse, directory, symlink, managed, [others], absent.  


```yaml
  files:
    recurse:
      recurse_group_name_1:
        - name: /path/to/dir
          source: salt://path/to/dir
          # user: root # optional, default salt's user
          # group: root # optional, default - salt's group
          # clean: False # optional, default False
          # dir_mode: 755 # optional, default handled by salt
          # file_mode: 644 # optional, default handled by salt
          ## https://docs.saltproject.io/en/latest/ref/states/all/salt.states.file.html#salt.states.file.recurse

    directory:
      dirs_group_name_1:
        - name: /path/to/dir 
          # user: root # optional, default salt's user
          # group: root # optional, default - salt's group
          # recurse: [user, group, mode] # optional, default handled by salt
          # dir_mode: 755 # optional, default handled by salt
          # file_mode: 644 # optional, default handled by salt
          # makedirs: False # optional, default False, create parent directories if not exists
          # force: False # optional, if path exists and is not a directory, delete path and create the directory
          # clean: False # optional, in context of this state - enshure directory is empty

          # apply: # optional, run arbitrary commands after file creation, commands are run as directory owner user
          #   - ps axu >> /path/to/dir/psaxu
          #   - lsblk >> /path/to/dir/lsblk
          #   - cmd: /home/user/user.sh
          #     runas: user
          #     cwd: /home/user
          #     only: onchanges # run command only if related directory is modified/created
                                # `only` can be one of the https://docs.saltproject.io/en/latest/ref/states/requisites.html#requisites-types
             

          ## https://docs.saltproject.io/en/latest/ref/states/all/salt.states.file.html#salt.states.file.directory

    symlink:
      symlinks_group_name_1:
        - name: /path/to/symlink
          target: /path/to/taget
          # user: root # optional, default salt's user
          # group: root # optional, default - salt's group
          # makedirs: False # optional, default False, create parent directories if not exists
          # force: False # optional, if path exists and is not a symlink, delete path and create the symlink
          ## https://docs.saltproject.io/en/latest/ref/states/all/salt.states.file.html#salt.states.file.symlink

    managed:
      managed_group_name_1:
        - name: /path/to/file # required, path to file on the server
          source: salt://path/to/file # required, path to file on the salt master
          contents: ...  # required, contents of the file, "source" and "contents" are mutually exclusive, "source" has precedence
          # user: root # optional, default salt's user
          # group: root # optional, default - salt's group
          # mode: 644 # optional, default handled by salt
          # makedirs: False # optional, default False, create parent directories if not exists
          # dir_mode: 755 # optional, default handled by salt
          # filetype: text # optional, default text, turns off jinja templating if set to "binary"
          # template: jinja # optional, default jinja, set template engine to use
          # values: # optional, default empty, pass the "defaults" values when file is templated with jinja
          #   key: value

          # apply: # optional, run arbitrary commands after file creation, commands are run as file owner user
          #   - update-grub
          #   - locale-gen
          #   - cmd: /home/user/user.sh
          #     runas: user
          #     cwd: /home/user
          #     only: onchanges # run command only if related file is modified/created
                                # `only` can be one of the https://docs.saltproject.io/en/latest/ref/states/requisites.html#requisites-types

          ## https://docs.saltproject.io/en/latest/ref/states/all/salt.states.file.html#salt.states.file.managed

    ## [others]
    append|prepend|blockreplace|missing|exists|line|uncomment|etc.:
      <others>_group_name_1:
        - param: value

          ## https://docs.saltproject.io/en/latest/ref/states/all/salt.states.file.html

    absent:
      absent_group_name_1:
        - name: /path/to/item

          ## https://docs.saltproject.io/en/latest/ref/states/all/salt.states.file.html#salt.states.file.absent
```

[others]: Is a generic catch all, and can potentially handle the other items from [salt.states.file](https://docs.saltproject.io/en/latest/ref/states/all/salt.states.file.html)


# Hooks and requisites  
One item of group can be a special `requisite`:  
```
  files:
    managed:
      files_group_name_1:
        - requisite:
            hook: <hook>
            <salt's requisite type>: ... # https://docs.saltproject.io/en/latest/ref/states/requisites.html#requisites-types 
        - name: /path/to/file # required, path to file on the server
          contents: "This file managed by salt"
```
## Hook usage
- `hook`s need to be defined in the parent (importer) state, in the right place. See [example](#general-include-example) below.  
- `hook` is only the pointer where to render yaml in the parent state   
- `files` without `hook` requisite defined will be rendered in the place where file_manager included without `hook`  
- `files` with `hook` requisite defined will be rendered only in the place with matching `hook`  
- `hook` and salt's requisites can be used alone or together.  
- salt's requisite - internal salt's system to create relationships between states.  

Salt's requisites can be tricky to use, but one may use it to change the files managing order without parent state modification. They can be used to hook up to any state with the known name or ID. When using salt's requisites pay attention to the order and place where requisite is used, since it has side-effects.  
For example, the file_manager state renders in the following order: `["recurse", "directory", "symlink", "managed", <others>, "absent"]`. And with the following requisite `requisite: {require [{git: "*"}]}` used in the group `directory` - `recurse` will be run as usual, and `directory`, `symlink` and so on, will be run _after_ all `git` states. That's because `require` will modify the execution order.  
Refer to <https://docs.saltproject.io/en/latest/ref/states/requisites.html> for further reading.  

# Usage in another state
To override defaults - define the `file_manager_defaults` dict  
`file_manager_defaults = {"default_user":"", "default_group":"", "replace_old":"empty", "replace_new":"empty"}`  
"" - means "None" in term of saltstack documentation, the default  

## Referred variables 
- `files` - required, dict, files items
- `hook` - optional, string, for usage in multiple places
- `file_manager_defaults` - optional, dict, default values for user/group and replacement text
- `extloop` - optional, integer, external loop counter

## General include example
```
      {%- with %}
        {%- set files = pillar.get("files", {}) %}
        {%- set hook = "when_the_sun_rises" %}
        {%- set extloop = loop_index %} 
        {%- set file_manager_defaults = {"default_user": _app_user, "default_group": _app_group,
                                         "replace_old": "__APP_NAME__", "replace_new": app_name} %}
        {%- include "_include/file_manager/init.sls" with context %}
      {%- endwith %}
```
