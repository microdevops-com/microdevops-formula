#!/bin/sh

set -eu

INSTALL_ROOT=/opt/microdevops
INSTALL_DIR=${INSTALL_ROOT}/static-build
ARCHIVE_URL=https://tools.sysadm.ws/files/tar/static-build.tar.gz

WORK_DIR=
LOCK_DIR=${INSTALL_ROOT}/.static-build-pre-flight.lock
LOCK_HELD=0
BACKUP_DIR=

log()
{
    printf '%s\n' "static-build pre-flight: $*" >&2
}

die()
{
    log "ERROR: $*"
    exit 1
}

cleanup()
{
    if [ -n "${BACKUP_DIR}" ] && [ -e "${BACKUP_DIR}" ]; then
        if [ -e "${INSTALL_DIR}" ]; then
            interrupted_dir=${WORK_DIR}/interrupted-static-build
            if ! mv "${INSTALL_DIR}" "${interrupted_dir}"; then
                log "ERROR: could not move interrupted replacement out of ${INSTALL_DIR}"
            fi
        fi
        if [ ! -e "${INSTALL_DIR}" ]; then
            if mv "${BACKUP_DIR}" "${INSTALL_DIR}"; then
                BACKUP_DIR=
            else
                log "ERROR: rollback failed; preserved backup is at ${BACKUP_DIR}"
            fi
        fi
    fi
    if [ -n "${WORK_DIR}" ] && [ -d "${WORK_DIR}" ]; then
        rm -rf "${WORK_DIR}"
    fi
    if [ "${LOCK_HELD}" -eq 1 ] && [ -d "${LOCK_DIR}" ]; then
        rmdir "${LOCK_DIR}" 2>/dev/null || true
    fi
}

trap cleanup 0
trap 'exit 1' 1 2 15

PYTHON_CHECK='
import os
import sys
import spwd
import ssl
import sqlite3

expected = os.path.realpath(sys.argv[1])
actual = os.path.realpath(sys.executable)
if actual != expected:
    raise RuntimeError("unexpected Python executable: {} != {}".format(actual, expected))

ssl.create_default_context()
connection = sqlite3.connect(":memory:")
connection.execute("select sqlite_version()").fetchone()
connection.close()
'

verify_runtime()
{
    runtime_dir=$1
    runtime_python=${runtime_dir}/root/bin/python3

    [ -x "${runtime_python}" ] || return 1
    "${runtime_python}" -c "${PYTHON_CHECK}" "${runtime_python}"
}

restore_backup()
{
    if [ -e "${INSTALL_DIR}" ]; then
        failed_dir=${WORK_DIR}/failed-static-build
        if ! mv "${INSTALL_DIR}" "${failed_dir}"; then
            log "ERROR: could not move the failed replacement out of ${INSTALL_DIR}"
            return 1
        fi
    fi

    if [ -n "${BACKUP_DIR}" ] && [ -e "${BACKUP_DIR}" ]; then
        if ! mv "${BACKUP_DIR}" "${INSTALL_DIR}"; then
            log "ERROR: rollback failed; preserved backup is at ${BACKUP_DIR}"
            return 1
        fi
        BACKUP_DIR=
    fi
}

if verify_runtime "${INSTALL_DIR}" >/dev/null 2>&1; then
    log "runtime is already installed and valid"
    exit 0
fi

[ "$(id -u)" -eq 0 ] || die "installation requires root"
[ "$(uname -s)" = Linux ] || die "unsupported operating system: $(uname -s)"

case "$(uname -m)" in
    x86_64|amd64)
        ;;
    *)
        die "unsupported architecture: $(uname -m)"
        ;;
esac

command -v tar >/dev/null 2>&1 || die "tar is required"

mkdir -p "${INSTALL_ROOT}" || die "could not create ${INSTALL_ROOT}"
if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
    die "another installation may be running; lock exists at ${LOCK_DIR}"
fi
LOCK_HELD=1

WORK_DIR=$(mktemp -d "${INSTALL_ROOT}/.static-build-pre-flight.XXXXXX") ||
    die "could not create a temporary directory under ${INSTALL_ROOT}"
ARCHIVE=${WORK_DIR}/static-build.tar.gz
EXTRACT_DIR=${WORK_DIR}/extract
CANDIDATE=${EXTRACT_DIR}/static-build
mkdir "${EXTRACT_DIR}" || die "could not create extraction directory"

log "downloading ${ARCHIVE_URL}"
if command -v wget >/dev/null 2>&1; then
    wget --no-verbose "${ARCHIVE_URL}" -O "${ARCHIVE}" ||
        die "download failed with wget"
elif command -v curl >/dev/null 2>&1; then
    curl --fail --location --silent --show-error "${ARCHIVE_URL}" --output "${ARCHIVE}" ||
        die "download failed with curl"
else
    die "wget or curl is required"
fi

log "extracting downloaded archive"
tar -xzf "${ARCHIVE}" -C "${EXTRACT_DIR}" ||
    die "archive extraction failed"

[ -d "${CANDIDATE}/root" ] ||
    die "archive layout is invalid: static-build/root is missing"
[ -x "${CANDIDATE}/root/bin/python3" ] ||
    die "archive layout is invalid: root/bin/python3 is missing or not executable"
[ -x "${CANDIDATE}/root/bin/python3.10" ] ||
    die "archive layout is invalid: root/bin/python3.10 is missing or not executable"
[ -L "${CANDIDATE}/root/lib/ld-musl-x86_64.so.1" ] ||
    die "archive layout is invalid: bundled musl loader is missing"
[ -f "${CANDIDATE}/root/lib/libc.so" ] ||
    die "archive layout is invalid: bundled musl libc is missing"

if [ -e "${INSTALL_DIR}" ]; then
    BACKUP_DIR=$(mktemp -d "${INSTALL_ROOT}/.static-build-backup.XXXXXX") ||
        die "could not reserve a backup path"
    rmdir "${BACKUP_DIR}" || die "could not prepare the backup path"
    mv "${INSTALL_DIR}" "${BACKUP_DIR}" ||
        die "could not move the existing installation to ${BACKUP_DIR}"
fi

if ! mv "${CANDIDATE}" "${INSTALL_DIR}"; then
    restore_backup || true
    die "could not move the downloaded runtime into ${INSTALL_DIR}"
fi

log "verifying installed Python runtime"
if ! verify_runtime "${INSTALL_DIR}"; then
    restore_backup || die "runtime verification failed and rollback failed"
    die "runtime verification failed; previous installation was restored"
fi

if [ -n "${BACKUP_DIR}" ] && [ -e "${BACKUP_DIR}" ]; then
    rm -rf "${BACKUP_DIR}" ||
        die "installation succeeded but old backup cleanup failed at ${BACKUP_DIR}"
    BACKUP_DIR=
fi

log "runtime installed and verified successfully"
