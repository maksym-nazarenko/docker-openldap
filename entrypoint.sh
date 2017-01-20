#!/bin/sh -a


#  Variables
SLAPD_PASSWORD=${SLAPD_PASSWORD:-''}
SLAPD_DOMAIN=${SLAPD_DOMAIN:-''}
SLAPD_SCHEMAS_INCLUDE=${SLAPD_SCHEMAS_INCLUDE:-''}
SLAPD_ORGANIZATION=${SLAPD_ORGANIZATION:-''}
SERVER_INIT_DIR=/init-server
DEBUG_LEVEL=${DEBUG_LEVEL:-0}
# =======================================
SLAPD_DOMAIN_NAME="$(echo $SLAPD_DOMAIN| sed -e 's/^\([^\.]*\)\..*$/\1/g')"
SLAPD_CONFIG_PASSWORD=${SLAPD_PASSWORD}
SLAPD_DATA_BASE_DIR="/var/lib/openldap/openldap-data"
SLAPD_DB_DATA_DIR="$SLAPD_DATA_BASE_DIR/${SLAPD_DOMAIN}"
SLAPD_CONFIG_BASE_DIR="/etc/openldap"
SLAPD_CONFIG_DIR="$SLAPD_CONFIG_BASE_DIR/slapd.d"
SLAPD_RUNAS_USER='ldap'
SLAPD_RUNAS_GROUP='ldap'
FIRST_RUN="no"
SERVICE_WAIT_TIMEOUT=30
# ==============================================
logMessage() {
    echo "$1"
}

logError() {
    logMessage "$1" >&2
}

checkSlapdConnection() {
  ldapsearch -H ldap://127.0.0.1:389/ -x >/dev/null 2>&1
  if [ $? -eq 32 ]; then
    return 0
  fi

  return 1
}

stopSlapd() {
  logMessage "Stopping slapd process"
  pkill /usr/sbin/slapd
  if ! pgrep /usr/sbin/slapd >/dev/null 2>&1; then
    return 0
  fi

  logMessage "Waiting for slapd process to finish"
  for i in $(seq 1 $SERVICE_WAIT_TIMEOUT) ; do
    if ! pgrep -f /usr/sbin/slapd >/dev/null 2>&1; then
      return 0
    fi
    echo -n "."
    sleep 1
  done

  return 1
}

startSlapd() {

  if ! pgrep -f /usr/sbin/slapd >/dev/null 2>&1; then
    logMessage "Starting SLAPD service"
    /usr/sbin/slapd -u $SLAPD_RUNAS_USER -g $SLAPD_RUNAS_GROUP -d $DEBUG_LEVEL -h 'ldapi:/// ldap:///' &
  fi

  if ! checkSlapdConnection; then
    logMessage "Waiting for slapd up and running"
    for i in $(seq 1 $SERVICE_WAIT_TIMEOUT) ; do
      if checkSlapdConnection; then
        return 0
      fi
      echo -n "."
      sleep 1
    done
  fi

  # the last resort
  if checkSlapdConnection; then
    return 0
  else
    logError "slapd process didn't start in $SERVICE_WAIT_TIMEOUT seconds"
    return 1
  fi

  return 1
}

initServer() {

  # cp -ar "$SLAPD_CONFIG_BASE_DIR" "$SLAPD_CONFIG_BASE_DIR".dist
  mkdir -p -m 0770 "$SLAPD_DB_DATA_DIR" "$SLAPD_CONFIG_DIR"
  rm -Rf "$SLAPD_DB_DATA_DIR"/* "$SLAPD_CONFIG_DIR"/* || true

  cp -a $SERVER_INIT_DIR/DB_CONFIG "$SLAPD_DB_DATA_DIR"/DB_CONFIG
  [ -d "$SERVER_INIT_DIR"/schema ] && cp -a $SERVER_INIT_DIR/schema/*.schema "$SLAPD_CONFIG_BASE_DIR"/schema/ || true

  if [ -z "$SLAPD_SCHEMAS_INCLUDE" ]; then
    SLAPD_SCHEMAS_INCLUDE='core,cosine'
  else
    SLAPD_SCHEMAS_INCLUDE="core,cosine,$SLAPD_SCHEMAS_INCLUDE"
  fi

  cat <<EOF > $SLAPD_CONFIG_BASE_DIR/slapd.conf
$(echo "$SLAPD_SCHEMAS_INCLUDE" | tr ',' "\n" | sed -e 's|^\(.*\)$|include /etc/openldap/schema/\1.schema|g')

pidfile		/var/run/openldap/slapd.pid
argsfile	/var/run/openldap/slapd.args
modulepath	/usr/lib/openldap
moduleload	back_hdb.so


database	hdb
suffix		"$SLAPD_DOMAIN_DC_FORMAT"
rootdn		"cn=admin,$SLAPD_DOMAIN_DC_FORMAT"
directory	$SLAPD_DB_DATA_DIR
index	objectClass	eq
EOF

slaptest -f "$SLAPD_CONFIG_BASE_DIR/slapd.conf" -F "$SLAPD_CONFIG_DIR" -d $DEBUG_LEVEL

sed -i '/^olcDatabase: {-1}frontend/a\
olcAccess: {0}to * by dn.exact=gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth manage by * break\
olcAccess: {1}to dn.exact="" by * read\
olcAccess: {2}to dn.base="cn=Subschema" by * read' "${SLAPD_CONFIG_DIR}/cn=config/olcDatabase={-1}frontend.ldif"

sed -i '/^olcDatabase: {0}config/a\
olcAccess: {0}to * by dn.exact=gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth manage by * break' "${SLAPD_CONFIG_DIR}/cn=config/olcDatabase={0}config.ldif"

  chown -R $SLAPD_RUNAS_USER:$SLAPD_RUNAS_GROUP "$SLAPD_DB_DATA_DIR"
  chown -R $SLAPD_RUNAS_USER:$SLAPD_RUNAS_GROUP "$SLAPD_CONFIG_DIR"

  # Init
  logMessage "Initializing LDAP directory"
  if ! startSlapd; then
    exit 1
  fi

  run-parts $SERVER_INIT_DIR/scripts.d/
  if ! stopSlapd; then
    exit 1
  fi

  return 0
}
# ==============================================
# prerequisite checks

if [ -f "$SLAPD_DB_DATA_DIR"/DB_CONFIG ]; then
  FIRST_RUN=no
else
  FIRST_RUN=yes
fi

if [ "$FIRST_RUN" = "yes" ]; then
  if [ -z "$SLAPD_PASSWORD" ]; then
      logError "Environment variable 'SLAPD_PASSWORD' is empty!"
      exit 1
  fi

  if [ -z "$SLAPD_DOMAIN" ]; then
      logError "Environment variable 'SLAPD_DOMAIN' is empty!"
      exit 1
  fi

  if [ -z "$SLAPD_ORGANIZATION" ]; then
      logError "Environment variable 'SLAPD_ORGANIZATION' is empty!"
      exit 1
  fi

  SLAPD_PASSWORD_HASH=$(slappasswd -n -s "$SLAPD_PASSWORD")
  SLAPD_DOMAIN_DC_FORMAT="dc=$(echo $SLAPD_DOMAIN| sed -e 's/\./,dc=/g')"

  if ! initServer; then
    logError "Can't initialize the server for the first time"
    exit 1
  fi
fi

# ===========================================================
logMessage "Starting OpenLDAP server"
if [ "${@:0:1}" = "-" ]; then
  exec /usr/sbin/slapd "$@"
else
  exec $@
fi
