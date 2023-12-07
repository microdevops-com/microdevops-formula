# file manager
The file manager state, pillar data example is listed below.  
The states are applied in the following order: recurse, directory, symlink, managed, absent.  

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
      files_group_name_1:
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

          ## https://docs.saltproject.io/en/latest/ref/states/all/salt.states.file.html#salt.states.file.managed

    absent:
      absent_group_name_1:
        - name: /path/to/item

          ## https://docs.saltproject.io/en/latest/ref/states/all/salt.states.file.html#salt.states.file.absent
```


## inside other state usage
To override defaults - define the `file_manager_defaults` dict  
`file_manager_defaults = {"default_user":"", "default_group":"", "replace_old":"empty", "replace_new":"empty"}`  
"" - means "None" in term of saltstack documentation, the default  
