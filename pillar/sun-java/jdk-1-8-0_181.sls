{% set java_version = '1.8.0_181' %}
java_home: /opt/java/jdk{{ java_version }}
java:
  prefix: /usr/share/java
  java_symlink: /usr/bin/java
  javac_symlink: /usr/bin/javac
  dl_opts: -b oraclelicense=accept-securebackup-cookie -L -s
  archive_type: tar
  version_name: jdk{{ java_version }}
  source_url: http://download.oracle.com/otn-pub/java/jdk/8u181-b13/96a7b8442fe848ef90c96a2fad6ed6d1/jdk-8u181-linux-x64.tar.gz
  source_hash: sha256=1845567095bfbfebd42ed0d09397939796d05456290fb20a83c476ba09f991d3
  jre_lib_sec: /usr/share/java/jdk{{ java_version }}/jre/lib/security
  java_real_home: /usr/share/java/jdk{{ java_version }}
  java_realcmd: /usr/share/java/jdk{{ java_version }}/bin/java
  javac_realcmd: /usr/share/java/jdk{{ java_version }}/bin/javac
