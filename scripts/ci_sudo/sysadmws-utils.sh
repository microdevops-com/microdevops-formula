#!/bin/bash
set -x

GRAND_EXIT=0
rm -f /srv/scripts/ci_sudo/$(basename $0).out
exec > >(tee /srv/scripts/ci_sudo/$(basename $0).out)
exec 2>&1

stdbuf -oL -eL echo "---"
stdbuf -oL -eL salt --force-color -t 300 '*' state.apply sysadmws-utils.sysadmws-utils queue=True || GRAND_EXIT=1
stdbuf -oL -eL echo "---"
stdbuf -oL -eL salt --force-color -t 300 '*' state.apply bulk_log.bulk_log queue=True || GRAND_EXIT=1
stdbuf -oL -eL echo "---"
stdbuf -oL -eL salt --force-color -t 300 '*' state.apply disk_alert.disk_alert queue=True || GRAND_EXIT=1
stdbuf -oL -eL echo "---"
stdbuf -oL -eL salt --force-color -t 300 '*' state.apply mysql_queries_log.mysql_queries_log queue=True || GRAND_EXIT=1
stdbuf -oL -eL echo "---"
stdbuf -oL -eL salt --force-color -t 300 '*' state.apply mysql_replica_checker.mysql_replica_checker queue=True || GRAND_EXIT=1
stdbuf -oL -eL echo "---"
stdbuf -oL -eL salt --force-color -t 300 '*' state.apply notify_devilry.notify_devilry queue=True || GRAND_EXIT=1

grep -q "ERROR" /srv/scripts/ci_sudo/$(basename $0).out && GRAND_EXIT=1

# 50 shades of red
grep -q "\[0;31m" /srv/scripts/ci_sudo/$(basename $0).out && GRAND_EXIT=1
grep -q "\[31m" /srv/scripts/ci_sudo/$(basename $0).out && GRAND_EXIT=1
grep -q "\[0;1;31m" /srv/scripts/ci_sudo/$(basename $0).out && GRAND_EXIT=1

exit $GRAND_EXIT
