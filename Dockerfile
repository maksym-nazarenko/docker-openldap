FROM alpine:3.4
MAINTAINER Maxim NAzarenko <maks.nazarenko@gmail.com>

RUN apk update && \
    apk add openldap openldap-back-hdb openldap-clients

COPY init-server /init-server
COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["-u", "ldap", "-g", "ldap", "-F", "/etc/openldap/slapd.d", "-h", "ldapi:/// ldap:///", "-d", "0"]
