#!/bin/bash
GRAND_EXIT=0
rm -f /srv/scripts/ci_sudo/$(basename $0).out
exec > >(tee /srv/scripts/ci_sudo/$(basename $0).out)
exec 2>&1

stdbuf -oL -eL echo "---"
stdbuf -oL -eL echo "NOTICE: CMD: salt --force-color -t 300 '*' state.apply sysadmws-utils.sysadmws-utils"
stdbuf -oL -eL salt --force-color -t 300 '*' state.apply sysadmws-utils.sysadmws-utils
stdbuf -oL -eL echo "---"
stdbuf -oL -eL echo "NOTICE: CMD: salt --force-color -t 300 '*' state.apply bulk_log.bulk_log"
stdbuf -oL -eL salt --force-color -t 300 '*' state.apply bulk_log.bulk_log
stdbuf -oL -eL echo "---"
stdbuf -oL -eL echo "NOTICE: CMD: salt --force-color -t 300 '*' state.apply disk_alert.disk_alert"
stdbuf -oL -eL salt --force-color -t 300 '*' state.apply disk_alert.disk_alert
stdbuf -oL -eL echo "---"
stdbuf -oL -eL echo "NOTICE: CMD: salt --force-color -t 300 '*' state.apply mysql_queries_log.mysql_queries_log"
stdbuf -oL -eL salt --force-color -t 300 '*' state.apply mysql_queries_log.mysql_queries_log
stdbuf -oL -eL echo "---"
stdbuf -oL -eL echo "NOTICE: CMD: salt --force-color -t 300 '*' state.apply mysql_replica_checker.mysql_replica_checker"
stdbuf -oL -eL salt --force-color -t 300 '*' state.apply mysql_replica_checker.mysql_replica_checker
stdbuf -oL -eL echo "---"
stdbuf -oL -eL echo "NOTICE: CMD: salt --force-color -t 300 '*' state.apply notify_devilry.notify_devilry"
stdbuf -oL -eL salt --force-color -t 300 '*' state.apply notify_devilry.notify_devilry

# Shades of red
grep -q "\[0;31m" /srv/scripts/ci_sudo/$(basename $0).out && GRAND_EXIT=1
grep -q "\[31m" /srv/scripts/ci_sudo/$(basename $0).out && GRAND_EXIT=1

exit $GRAND_EXIT
