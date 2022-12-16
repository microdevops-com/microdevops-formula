{% from "ufw/vars.jinja" import vars with context %}

ufw:
  allow:
    heartbeat_mesh_receiver_all_servers:
      proto: tcp
      from:
        {{ vars["All_Servers"] }}
      to_port: 15987
