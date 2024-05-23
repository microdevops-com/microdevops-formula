# Exporter

## Minimum viable example

```yaml
exporter:
  node1:
    type: node
  statsd:
    type: statsd
```

`salt ... state.apply exporter`

This will install exporters as:  
```
/opt/exporter/node/node/node_exporter
/opt/exporter/statsd/statsd/statsd_exporter
```
and run as   
```
exporter_node.service
exporter_statsd.service
```

## Exporter targeting
There is two pillar keys to target needed exporter if there is deployed many:  
`exporter_type` - only full match by type  
`exporter_name` - valid regex (not glob), e.g. `node.*` or `^node1$`
```
salt ... state.apply exporter pillar='{exporter_type: <type>, and/or exporter_name: <name> or regex}'
```


## Pillar structure
See [pillar.example](./pillar.example)  
pillar structure is almost the same as in [defaults.yaml structure](#defaultsyaml-structure), with a few differences:
- first level key under `exporter` which is `<name>` declares exporter's name, which allows to run multiple exporters of the same type with different names and settings
- under `<name>` key `type` declares the exporter type. 
The rest is the same as in `defaults.yaml` (which sets the defaults), and can be overriden from pillar.

```yaml
exporter:
  <name>: # later will be available as {name} and systemd service will be named as `exporter_<name>.service`
    type: # exporter type, see available names in `defaults.yaml` under `exporter`
    version: ...
    install_dir: ...
    args:  ...
```

## Fstrings
### Description
To make things more flexible, there is some placeholders, that will be filled up with relative data at state renter time:
- `tag`
  - if `version: latest`, and `store: github` then latest tag name will be fetched and set to this placeholder automatically
  - if `store: direct` or `store: dockerhub` - `tag` will be set with `version` contents
- `tag_vstrip` - same as above, without letter `v` from the left side
- `osarch`, `cpuarch`, `kernel`, `kernel_lower` - grains
- `name` - exporter's `<name>` from pillar
- `type` - exporter's type
- `file` - path to downloaded file. For use with `move`
- `install_dir` - path to directory where binary file will be
- `args` - string from pillar, for use in `exec`

### Availability

FSOURCE: `{tag}, {tag_vstrop}, {osarch}, {cpuarch}, {kernel}, {kernel_lower}`  
FBASE: `{name}, {type}, {file}, {install_dir}, {args}`  

- `source`: FSOURCE
- `install_dir`: `{name}, {type}`
- `venv:requirements_txt`: FBASE
- `extractor:platform`: FSOURCE
- `move:src`: FBASE
- `move:dst`: FBASE
- `exec`: FBASE
- `args`: FBASE without `args`
- `files`: FBASE in `name` parameters


## `defaults.yaml` structure
`defaults.yaml` defines the sane defaults in this state for particular exporter type. Later, declared type can be used in pillar with theese defaults.  

One of the `move`, `tar` or `extractor` is required, because this is the main step: place the binary file.

```
exporter: 
  <type>: # - defines exporter type, holds configuration for this exporter  
    store: # - required, string, the name of remote, used for automatic version/tag fetching, can be one of github, dockerhub, direct  
    source # - required, string, uri of the file or archive with exporter executable  
    install_dir: # - required, string, path to the root dir where binary file will be placed  

    venv: # - optional, dict, install python virtualenv at {install_dir}/venv  
      requirements_txt: # - optional, string, path to the requirements.txt if code has them after unpacking  
      requirements: # - optional, list of strings, in format of requirements.txt, one requirement per entry  

    tar: # - optional, dict, if remote file is a tar archive - unpack, and pass arbitrary arguments  
      args: # - optional, string, default "", passed as is to tar command before --file argument  
      unpack: # - optional, string, default "", bassed as is to tar command at the end, space separated list of files to unpack from archive, empty means all files  

    extractor: # - optional, dict, extract docker image to local directory, allows install statically linked binaries which are distributed only as docker images  
      dir: # - optional, string, default output, directory for unpacking docker image  
      clean: # - optional, bool, default true, delete directory in which contents of docker was unpacked after configuring exporter  
      platform: # - required, string, platform (e.g. linux/amd64) of the docker image if available  

    move: # - optional, dict, just move file if source is already executable file  
      src: # - required, string, source file  
      dst: # - required, string, destination file (not directory)  
    exec: # - required, string, full path to the executable binary  
    args: # - required, string, will be available as {args}  
```

example:
```yaml
exporter:
  <type>: 
    store: github | direct | dockerhub
    version: latest | v0.1.1
    source: https://..., salt://..., path/to/local/file
    install_dir: "/opt/exporter/{type}/{name}"

    venv:
      requirements_txt: "{install_dir}/requirements.txt"
      requirements:
        - gunicorn==20.1
        - tzdata==2024.1
        - xmltodict

    tar:
      args: '--strip-components=1 --no-anchored'
      unpack: "file_name_in_archive" 

    extractor:
      dir: output
      clean: False
      platform: "{kernel_lower}/{osarch}"

    move:
      src: "{file}"
      dst: "{install_dir}/{type}_exporter"

    exec: "{install_dir}/{type}_exporter {args}"
    args: ""
```
