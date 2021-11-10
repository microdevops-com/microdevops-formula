#!/bin/bash
# Consul parameters must match the instance settings
# This flag controls the datacenter in which the agent is running. 
# If not provided, it defaults to "dc1".
# https://www.consul.io/docs/agent/options#_datacenter
CONSUL_DC="dc1"
# By default, Consul responds to DNS queries in the "consul." domain.
# https://www.consul.io/docs/agent/options#_domain
CONSUL_DOMAIN="consul"

# Set your certificate subject parameters
ORG="My Organization"
CN="${1} CA ROOT"
EMAIL="master@example.com"
SUBJ_BASE="/O=${ORG}/emailAddress=${EMAIL}"
CA_SUBJ="/CN=${CN}${SUBJ_BASE}"
KEY_SIZE=4096
DAYS=36500
if [[ -z "${1}" || -z "${2}" ]] || [[ "${2}" != client && "${2}" != server ]] || [[ "${2}" == server && -z "${3}" ]]; then
  echo "Usage:"
  echo "  ${0} <directory> server <fqdn>"
  echo "  ${0} <directory> client [fqdn]"
  echo
  echo "Example:"
  echo "  ${0} tls_dir server node1.consul.example.com"
  echo "  ${0} tls_dir client"
  exit 1
fi
# Directory for certs
BASEDIR="$(dirname $(realpath ${0}))"/"${1}"
mkdir "${BASEDIR}" -p

# Generate a CA KEY
if [[ -f "${BASEDIR}"/ca.key ]]; then
	echo
	echo "WARNING: FILE \"${BASEDIR}/ca.key\" ALREADY EXIST"
	echo -n "TYPE \"yes\" IF YOU WANT TO NEW \"${BASEDIR}/ca.key\" : [no] : "
	read NEW_CA_KEY
	echo
	if [[ "${NEW_CA_KEY}" == 'yes' ]]; then
		openssl genrsa -out "${BASEDIR}"/ca.key "$KEY_SIZE"
	fi
else 
	openssl genrsa -out "${BASEDIR}"/ca.key "$KEY_SIZE"
	NEW_CA_KEY=yes
fi

# Generate a CA CERT
if [[ "${NEW_CA_KEY}" == 'yes' || ! -f "${BASEDIR}"/ca.crt ]]; then
	openssl req -x509 -new -nodes -key "${BASEDIR}"/ca.key -subj "$CA_SUBJ" -days "${DAYS}" -out "${BASEDIR}"/ca.crt -sha256
else
  echo
  echo "WARNING: FILE \"${BASEDIR}/ca.crt\" ALREADY EXIST"
  echo -n "TYPE \"yes\" IF YOU WANT TO NEW \"${BASEDIR}/ca.crt\" : [no] : "
  read NEW_CA_CRT
  echo
  if [[ "${NEW_CA_CRT}" == 'yes' ]]; then
    openssl req -x509 -new -nodes -key "${BASEDIR}"/ca.key -subj "$CA_SUBJ" -days "${DAYS}" -out "${BASEDIR}"/ca.crt -sha256
  fi
fi

# Generate a KEY CSR and CERT for SERVER
if [[ "${2}" == 'server' ]]; then
# Generate a KEY for SERVER
	if [[ "${NEW_CA_KEY}" == 'yes' || ! -f "${BASEDIR}"/"${3}".key ]]; then
		openssl genrsa -out "${BASEDIR}"/"${3}".key "$KEY_SIZE"
    NEW_KEY=yes
	else
    echo
    echo "WARNING: FILE \"${BASEDIR}/${3}.key\" ALREADY EXIST"
    echo -n "TYPE \"yes\" IF YOU WANT TO NEW \"${BASEDIR}/${3}.key\" : [no] : "
    read NEW_KEY
    echo
    if [[ "${NEW_KEY}" == 'yes' ]]; then
      openssl genrsa -out "${BASEDIR}"/"${3}".key "$KEY_SIZE"
    fi
	fi
# Generate a CSR for SERVER
  if [[ "${NEW_KEY}" == 'yes' || ! -f "${BASEDIR}"/"${3}".csr ]]; then
    openssl req -new -key "${BASEDIR}"/"${3}".key -subj "$SUBJ_BASE" -out "${BASEDIR}"/"${3}".csr -sha256
    NEW_CSR=yes
  else
    echo
    echo "WARNING: FILE \"${BASEDIR}/${3}.csr\" ALREADY EXIST"
    echo -n "TYPE \"yes\" IF YOU WANT TO NEW \"${BASEDIR}/${3}.csr\" : [no] : "
    read NEW_CSR
    echo
    if [[ "${NEW_CSR}" == 'yes' ]]; then
      openssl req -new -key "${BASEDIR}"/"${3}".key -subj "$SUBJ_BASE" -out "${BASEDIR}"/"${3}".csr -sha256
    fi
  fi
# Generate a CRT for SERVER
	if [[ "${NEW_KEY}" == 'yes' || "${NEW_CSR}" == 'yes' || ! -f "${BASEDIR}"/"${3}".crt ]]; then
    openssl x509 -req -days "${DAYS}" -in "${BASEDIR}"/"${3}".csr -CA "${BASEDIR}"/ca.crt -CAkey "${BASEDIR}"/ca.key -CAcreateserial -out "${BASEDIR}"/"${3}".crt -extfile <( printf "subjectAltName=DNS.1:${2}.${CONSUL_DC}.${CONSUL_DOMAIN},DNS.2:${3},DNS.3:localhost,IP.1:127.0.0.1" )
    NEW_CRT=yes
  else
		echo
    echo "WARNING: FILE \"${BASEDIR}/${3}.crt\" ALREADY EXIST"
    echo -n "TYPE \"yes\" IF YOU WANT TO NEW \"${BASEDIR}/${3}.crt\" : [no] : "
    read NEW_CRT
    echo
    if [[ "${NEW_CRT}" == 'yes' ]]; then
			openssl x509 -req -days "${DAYS}" -in "${BASEDIR}"/"${3}".csr -CA "${BASEDIR}"/ca.crt -CAkey "${BASEDIR}"/ca.key -CAcreateserial -out "${BASEDIR}"/"${3}".crt -extfile <( printf "subjectAltName=DNS.1:${2}.${CONSUL_DC}.${CONSUL_DOMAIN},DNS.2:${3},DNS.3:localhost,IP.1:127.0.0.1" )
		fi
	fi
fi
# Generate a KEY CSR and CERT for CLIENT
if [[ "${2}" == 'client' ]]; then
# Generate a common KEY for CLIENT
	if [ -z "${3}" ]; then
    if [[ "${NEW_CA_KEY}" == 'yes' || ! -f "${BASEDIR}"/agent-"${2}".key ]]; then
      openssl genrsa -out "${BASEDIR}"/agent-"${2}".key "$KEY_SIZE"
      NEW_KEY=yes
    else
      echo
      echo "WARNING: FILE \"${BASEDIR}/agent-${2}.key\" ALREADY EXIST"
      echo -n "TYPE \"yes\" IF YOU WANT NEW \"${BASEDIR}/agent-${2}.key\" : [no] : "
      read NEW_KEY
      echo
      if [[ "${NEW_KEY}" == yes ]]; then
        openssl genrsa -out "${BASEDIR}"/agent-"${2}".key "$KEY_SIZE"
      fi
    fi
# Generate a common CSR for CLIENT
		if [[ "${NEW_KEY}" == 'yes' || ! -f "${BASEDIR}"/agent-"${2}".csr ]]; then
      openssl req -new -key "${BASEDIR}"/agent-"${2}".key -subj "$SUBJ_BASE" -out "${BASEDIR}"/agent-"${2}".csr -sha256
      NEW_CSR=yes
    else
			echo
      echo "WARNING: FILE \"${BASEDIR}/agent-${2}.csr\" ALREADY EXIST"
      echo -n "TYPE \"yes\" IF YOU WANT TO NEW \"${BASEDIR}/agent-${2}.csr\" : [no] : "
      read NEW_CSR
      echo
			if [[ "${NEW_CSR}" == 'yes' ]]; then
	      openssl req -new -key "${BASEDIR}"/agent-"${2}".key -subj "$SUBJ_BASE" -out "${BASEDIR}"/agent-"${2}".csr -sha256
			fi
		fi
# Generate a common CRT for CLIENT
		if [[ "${NEW_KEY}" == 'yes' || "${NEW_CSR}" == 'yes' || ! -f "${BASEDIR}"/agent-"${2}".crt ]]; then
      openssl x509 -req -days "${DAYS}" -in "${BASEDIR}"/agent-"${2}".csr -CA "${BASEDIR}"/ca.crt -CAkey "${BASEDIR}"/ca.key -CAcreateserial -out "${BASEDIR}"/agent-"${2}".crt -extfile <( printf "subjectAltName=DNS.1:${2}.${CONSUL_DC}.${CONSUL_DOMAIN},DNS.2:localhost,IP.1:127.0.0.1" )
      NEW_CRT=yes
    else
			echo
      echo "WARNING: FILE \"${BASEDIR}/agent-${2}.crt\" ALREADY EXIST"
      echo -n "TYPE \"yes\" IF YOU WANT TO NEW \"${BASEDIR}/agent-${2}.crt\" : [no] : "
      read NEW_CRT
      echo
			if [[ "${NEW_CRT}" == 'yes' ]]; then
        openssl x509 -req -days "${DAYS}" -in "${BASEDIR}"/agent-"${2}".csr -CA "${BASEDIR}"/ca.crt -CAkey "${BASEDIR}"/ca.key -CAcreateserial -out "${BASEDIR}"/agent-"${2}".crt -extfile <( printf "subjectAltName=DNS.1:${2}.${CONSUL_DC}.${CONSUL_DOMAIN},DNS.2:localhost,IP.1:127.0.0.1" )
			fi
		fi
	else
# Generate a named KEY for CLIENT
    if [[ "${NEW_CA_KEY}" == 'yes' || ! -f "${BASEDIR}"/"${3}".key ]]; then
      openssl genrsa -out "${BASEDIR}"/"${3}".key "$KEY_SIZE"
      NEW_KEY=yes
    else
			echo
      echo "WARNING: FILE \"${BASEDIR}/${3}.key\" ALREADY EXIST"
      echo -n "TYPE \"yes\" IF YOU WANT TO NEW \"${BASEDIR}/${3}.key\" : [no] : "
      read NEW_KEY
      echo
      if [[ "${NEW_KEY}" == 'yes' ]]; then
				openssl genrsa -out "${BASEDIR}"/"${3}".key "$KEY_SIZE"
			fi
		fi
# Generate a named CSR for CLIENT
		if [[ "${NEW_KEY}" == 'yes' || ! -f "${BASEDIR}"/"${3}".csr ]]; then
      openssl req -new -key "${BASEDIR}"/"${3}".key -subj "$SUBJ_BASE" -out "${BASEDIR}"/"${3}".csr -sha256
      NEW_CSR=yes
    else
			echo
      echo "WARNING: FILE \"${BASEDIR}/${3}.csr\" ALREADY EXIST"
      echo -n "TYPE \"yes\" IF YOU WANT TO NEW \"${BASEDIR}/${3}.csr\" : [no] : "
      read NEW_CSR
      echo
      if [[ "${NEW_CSR}" == 'yes' ]]; then
        openssl req -new -key "${BASEDIR}"/"${3}".key -subj "$SUBJ_BASE" -out "${BASEDIR}"/"${3}".csr -sha256
			fi
		fi
# Generate a named CRT for CLIENT
		if [[ "${NEW_KEY}" == 'yes' || "${NEW_CSR}" == 'yes' || ! -f "${BASEDIR}"/"${3}".crt ]]; then
      openssl x509 -req -days "${DAYS}" -in "${BASEDIR}"/"${3}".csr -CA "${BASEDIR}"/ca.crt -CAkey "${BASEDIR}"/ca.key -CAcreateserial -out "${BASEDIR}"/"${3}".crt -extfile <( printf "subjectAltName=DNS.1:${2}.${CONSUL_DC}.${CONSUL_DOMAIN},DNS.2:localhost,IP.1:127.0.0.1" )
      NEW_CRT=yes
    else
			echo
      echo "WARNING: FILE \"${BASEDIR}/${3}.crt\" ALREADY EXIST"
      echo -n "TYPE \"yes\" IF YOU WANT TO NEW \"${BASEDIR}/${3}.csr\" : [no] : "
      read NEW_CRT
      echo
      if [[ "${NEW_CRT}" == 'yes' ]]; then
		    openssl x509 -req -days "${DAYS}" -in "${BASEDIR}"/"${3}".csr -CA "${BASEDIR}"/ca.crt -CAkey "${BASEDIR}"/ca.key -CAcreateserial -out "${BASEDIR}"/"${3}".crt -extfile <( printf "subjectAltName=DNS.1:${2}.${CONSUL_DC}.${CONSUL_DOMAIN},DNS.2:localhost,IP.1:127.0.0.1" )
			fi
		fi
	fi
fi
# Clean up csrs
rm "${BASEDIR}"/*.csr