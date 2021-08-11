#!/usr/bin/env bash
set -e

# By default do not send notify
NOTIFY_SEND=0

# Pipelines for rsnapshot_backup
if [[ -n "$RSNAPSHOT_BACKUP_TYPE" ]]; then

	NOTIFY_SERVICE=pipeline_rsnapshot_backup
	NOTIFY_RESOURCE=${SALT_MINION}

	# Failed job on any stage or check_alive_minions failure - send notify
	if [[ "$CI_JOB_STATUS" == "failed" || "$CHECK_ALIVE_MINIONS" == "failed" ]]; then

		# Consider check_backup as major
		if [[ $CI_JOB_NAME =~ rsnapshot_backup_check_backup ]]; then
			NOTIFY_SEVERITY=major
			NOTIFY_SEND=1
			NOTIFY_EVENT=pipeline_rsnapshot_backup_check_backup_failed
			NOTIFY_VALUE=failed
			NOTIFY_TEXT="Pipeline for rsnapshot_backup failed on job check_backup ${CI_JOB_URL}"
			NOTIFY_CORRELATE='["pipeline_rsnapshot_backup_check_coverage_failed","pipeline_rsnapshot_backup_failed","pipeline_rsnapshot_backup_ok"]'

		# Consider check_coverage as minor
		elif [[ $CI_JOB_NAME =~ rsnapshot_backup_check_coverage ]]; then
			NOTIFY_SEVERITY=minor
			NOTIFY_SEND=1
			NOTIFY_EVENT=pipeline_rsnapshot_backup_check_coverage_failed
			NOTIFY_VALUE=failed
			NOTIFY_TEXT="Pipeline for rsnapshot_backup failed on job check_coverage ${CI_JOB_URL}"
			NOTIFY_CORRELATE='["pipeline_rsnapshot_backup_check_backup_failed","pipeline_rsnapshot_backup_failed","pipeline_rsnapshot_backup_ok"]'

		# All other stages are critical
		else
			NOTIFY_SEVERITY=critical
			NOTIFY_SEND=1
			NOTIFY_EVENT=pipeline_rsnapshot_backup_failed
			NOTIFY_VALUE=failed
			NOTIFY_TEXT="Pipeline for rsnapshot_backup failed ${CI_JOB_URL}"
			NOTIFY_CORRELATE='["pipeline_rsnapshot_backup_check_backup_failed","pipeline_rsnapshot_backup_check_coverage_failed","pipeline_rsnapshot_backup_ok"]'
		fi

	# Successful job only at last stage - check_coverage - send ok
	elif [[ "$CI_JOB_STATUS" == "success" ]]; then

		if [[ $CI_JOB_NAME =~ rsnapshot_backup_check_coverage ]]; then
			NOTIFY_SEVERITY=ok
			NOTIFY_SEND=1
			NOTIFY_EVENT=pipeline_rsnapshot_backup_ok
			NOTIFY_VALUE=ok
			NOTIFY_TEXT="Pipeline for rsnapshot_backup succeeded ${CI_PIPELINE_URL}"
			NOTIFY_CORRELATE='["pipeline_rsnapshot_backup_check_backup_failed","pipeline_rsnapshot_backup_check_coverage_failed","pipeline_rsnapshot_backup_failed"]'
		fi

	fi

# Pipelines for salt_cmd
elif [[ -n "$SALT_CMD" ]]; then

	NOTIFY_SERVICE=pipeline_salt_cmd
	SALT_CMD_DECODED=$(echo ${SALT_CMD} | base64 -d)
	SALT_CMD_SAFE=$(echo ${SALT_CMD_DECODED} | sed -r s/[^a-zA-Z0-9]+/-/g | sed -r s/^-+\|-+$//g | cut -c -80)
	NOTIFY_RESOURCE=${SALT_MINION}:${SALT_CMD_SAFE}

	# Failed job on any stage or check_alive_minions failure - send notify
	if [[ "$CI_JOB_STATUS" == "failed" || "$CHECK_ALIVE_MINIONS" == "failed" ]]; then

		# Consider any failure as major
		NOTIFY_SEVERITY=major
		NOTIFY_SEND=1
		NOTIFY_EVENT=pipeline_salt_cmd_failed
		NOTIFY_VALUE=failed
		NOTIFY_TEXT="Pipeline for salt_cmd failed on job ${CI_JOB_URL}"
		NOTIFY_CORRELATE='["pipeline_salt_cmd_ok"]'

	# Successful job only at last stage - salt_cmd - send ok
	elif [[ "$CI_JOB_STATUS" == "success" ]]; then

		if [[ $CI_JOB_NAME =~ salt_cmd ]]; then
			NOTIFY_SEVERITY=ok
			NOTIFY_SEND=1
			NOTIFY_EVENT=pipeline_salt_cmd_ok
			NOTIFY_VALUE=ok
			NOTIFY_TEXT="Pipeline for salt_cmd succeeded ${CI_PIPELINE_URL}"
			NOTIFY_CORRELATE='["pipeline_salt_cmd_failed"]'
		fi

	fi

fi

# Do not send SALT_CMD_DECODED in attributes as it may contain quotes, check original command in job logs if needed
if [[ "$NOTIFY_SEND" == "1" ]]; then
	echo '{
		"severity": "'${NOTIFY_SEVERITY}'",
		"service": "'${NOTIFY_SERVICE}'",
		"resource": "'${NOTIFY_RESOURCE}'",
		"event": "'${NOTIFY_EVENT}'",
		"value": "'${NOTIFY_VALUE}'",
		"group": "pipeline",
		"text": "'${NOTIFY_TEXT}'",
		"origin": ".gitlab-ci.yml",
		"correlate": '${NOTIFY_CORRELATE}',
		"attributes": {
			"salt_minion": "'${SALT_MINION}'",
			"salt_timeout": "'${SALT_TIMEOUT}'",
			"salt_cmd_safe": "'${SALT_CMD_SAFE}'",
			"rsnapshot_backup_type": "'${RSNAPSHOT_BACKUP_TYPE}'",
			"ssh_jump": "'${SSH_JUMP}'",
			"ssh_host": "'${SSH_HOST}'",
			"ssh_port": "'${SSH_PORT}'",
			"ci_job_status": "'${CI_JOB_STATUS}'",
			"ci_job_name": "'${CI_JOB_NAME}'",
			"ci_job_url": "'${CI_JOB_URL}'",
			"ci_pipeline_url": "'${CI_PIPELINE_URL}'"
		}
	}' | /opt/sysadmws/notify_devilry/notify_devilry.py
else
	echo Not sending as NOTIFY_SEND == 0
fi
