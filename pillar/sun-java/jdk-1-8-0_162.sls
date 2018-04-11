{% set java_version = '1.8.0_162' %}
java_home: /opt/java/jdk{{ java_version }}
java:
  prefix: /usr/share/java
  java_symlink: /usr/bin/java
  javac_symlink: /usr/bin/javac
  dl_opts: -b oraclelicense=accept-securebackup-cookie -L -s
  archive_type: tar
  version_name: jdk{{ java_version }}
  source_url: http://download.oracle.com/otn-pub/java/jdk/8u162-b12/0da788060d494f5095bf8624735fa2f1/jdk-8u162-linux-x64.tar.gz
  source_hash: sha256=68ec82d47fd9c2b8eb84225b6db398a72008285fafc98631b1ff8d2229680257
  jre_lib_sec: /usr/share/java/jdk{{ java_version }}/jre/lib/security
  java_real_home: /usr/share/java/jdk{{ java_version }}
  java_realcmd: /usr/share/java/jdk{{ java_version }}/bin/java
  javac_realcmd: /usr/share/java/jdk{{ java_version }}/bin/javac
