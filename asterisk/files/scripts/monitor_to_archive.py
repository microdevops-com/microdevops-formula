#!/usr/bin/python3

import os
import paramiko
import time
import glob
import logging

HOST_NAME = "{{ host_archive }}"
USER_NAME = "{{ user_archive }}"
KEY_FILE_NAME = "{{ ssh_file }}"
SRC_DIR = "/var/spool/asterisk/monitor"
DST_DIR ="{{ des_dir }}"
MIN_OLDER = "3"
HOUR_UNDER = "2"
FILE_LOG = "/var/log/asterisk/monitor_to_archive.log"

### level = ERROR | DEBUG | INFO | WARNING | CRITICAL
logging.basicConfig(filename = FILE_LOG, level = logging.ERROR, format = '%(asctime)s:%(levelname)s:%(name)s:%(message)s')

mminOld = time.time() - (60 * int(MIN_OLDER))
mtimeUnd = time.time() - (60 * 60 * int(HOUR_UNDER))

srcFiles = glob.iglob(SRC_DIR + '/**/*',recursive=True )


try:
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(HOST_NAME, username=USER_NAME, key_filename=KEY_FILE_NAME)
    sftp = ssh.open_sftp()
except Exception as err:
    logging.error(" err ssh " + str(err))
    sftp.close()
    ssh.close()
    exit()


for file in srcFiles:
    try:
        fileMTime = os.path.getmtime(file)

        if os.path.isfile(file) and fileMTime > mtimeUnd and fileMTime < mminOld:
            dstPath = file.replace(SRC_DIR, DST_DIR)
            dstPathDir = os.path.dirname(dstPath)
            dstPathSubDir = dstPathDir
            listNotDir = []

            while dstPathDir.split("/"):
                try:
                    sftp.chdir(dstPathSubDir)
                    if len(listNotDir):
                        for mkdirNew in listNotDir:
                            sftp.mkdir(os.path.join(dstPathSubDir, mkdirNew))
                            dstPathSubDir = os.path.join(dstPathSubDir, mkdirNew)
                    break
                except IOError:
                    dstPathSubDir, notDir = os.path.split(dstPathSubDir)
                    listNotDir.insert(0, notDir)

            sftp.put(file, dstPath)

    except Exception as err:
        logging.error(" err file " + file + " " + str(err))
        print(" err file " + file + " " + str(err))
        continue

sftp.close()
ssh.close()
exit()



