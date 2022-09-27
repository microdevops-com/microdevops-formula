#!/bin/bash

#YEAR=$1
#MONTH=$2
#DAY=$3
#CALLFILENAME=$4

FILE=/var/spool/asterisk/monitor/$1/$2/$3/$4

if [ -f "$FILE.wav" ]; then

/usr/bin/lame -h -b 192 $FILE.wav $FILE.mp3 && /bin/rm -rf $FILE.wav

mysqlpass="$(grep "AMPDBPASS" /etc/freepbx.conf | awk '{printf $3}' | sed -e "s/['|;]//g")"

querty="UPDATE cdr SET recordingfile=replace(recordingfile,\".wav\",\".mp3\") WHERE recordingfile=\"$4.wav\";"
mysql --user=freepbxuser --password="$mysqlpass" asteriskcdrdb <<< "$querty"

querty="UPDATE PT1C_cdr SET recordingfile=replace(recordingfile,\".wav\",\".mp3\") WHERE recordingfile=\"$4.wav\";"
mysql --user=freepbxuser --password="$mysqlpass" asteriskcdrdb <<< "$querty"

/bin/echo "Transfer complete! Before: $FILE.wav, after: $FILE.mp3" >> /var/log/asterisk/full

else

/bin/echo "Transfer failure! File not found!" >> /var/log/asterisk/full

fi

# !!! Post Call Recording Script !!!
# /var/lib/asterisk/agi-bin/realtime_transfer.sh ^{YEAR} ^{MONTH} ^{DAY} ^{CALLFILENAME}
