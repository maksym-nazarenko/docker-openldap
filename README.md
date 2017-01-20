Usage
-----

```shell
docker run \
  -it \
  --name openldap \
  -e SLAPD_ORGANIZATION='My Org, Inc.' \
  -e SLAPD_PASSWORD='pass' \
  -e SLAPD_DOMAIN='domain.local' \
  -p 127.0.0.1:389:389 \
  -v $PWD/data/slapd.d:/etc/openldap/slapd.d \
  -v $PWD/data/ldap_db:/var/lib/openldap/openldap-data \
  openldap
```

Variables
---------

**SLAPD_PASSWORD**

Password for default admin user (cn=admin,cn=config and cn=admin,dc=you,dc=domain,dc=com)

**SLAPD_DOMAIN=**

LDAP domain to be created.
The form of the variable is a simple FQDN: `my.domain.com`

**SLAPD_ORGANIZATION**

Organization name for the root `Organization` object
