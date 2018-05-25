{% set java_version = '1.8.0_172' %}
java_home: /opt/java/jdk{{ java_version }}
java:
  prefix: /usr/share/java
  java_symlink: /usr/bin/java
  javac_symlink: /usr/bin/javac
  dl_opts: -b oraclelicense=accept-securebackup-cookie -L -s
  archive_type: tar
  version_name: jdk{{ java_version }}
  source_url: http://download.oracle.com/otn-pub/java/jdk/8u172-b11/a58eab1ec242421181065cdc37240b08/jdk-8u172-linux-x64.tar.gz
  source_hash: sha256=28a00b9400b6913563553e09e8024c286b506d8523334c93ddec6c9ec7e9d346
  jre_lib_sec: /usr/share/java/jdk{{ java_version }}/jre/lib/security
  java_real_home: /usr/share/java/jdk{{ java_version }}
  java_realcmd: /usr/share/java/jdk{{ java_version }}/bin/java
  javac_realcmd: /usr/share/java/jdk{{ java_version }}/bin/javac
