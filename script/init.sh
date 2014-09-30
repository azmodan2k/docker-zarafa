# Initialization and Setup for a new
# created Docker Container
#
# Author: Tobias Mandjik <webmaster@leckerbeef.de>
#

# (LDAP) DELETE OLD DATABASES
echo "[LDAP] DELETING OLD DATABASES"
rm -rf /var/lib/ldap/*

# (LDAP) SET VALUES FOR CONFIGURATION
echo "[LDAP] SETTING NEW CONFIGURATION VALUES"
echo "slapd slapd/password1 password ${LB_LDAP_PASSWORD}" | debconf-set-selections
echo "slapd slapd/password2 password ${LB_LDAP_PASSWORD}" | debconf-set-selections
echo "slapd slapd/internal/adminpw password ${LB_LDAP_PASSWORD}" | debconf-set-selections
echo "slapd slapd/internal/generated_adminpw passowrd ${LB_LDAP_PASSWORD}" | debconf-set-selections
echo "slapd slapd/allow_ldap_v2 boolean false" | debconf-set-selections
echo "slapd slapd/invalid_config boolean true" | debconf-set-selections
echo "slapd slapd/move_old_database boolean false" | debconf-set-selections
#echo "slapd slapd/upgrade_slapcat_failure error" | debconf-set-selections
echo "slapd slapd/backend select HDB" | debconf-set-selections
echo "slapd shared/organization string ${LB_LDAP_DN}" | debconf-set-selections
echo "slapd slapd/domain string ${LB_MAILDOMAIN}" | debconf-set-selections
echo "slapd slapd/no_configuration boolean false" | debconf-set-selections
echo "slapd slapd/dump_database_destdir string /var/backups/slapd-VERSION" | debconf-set-selections
echo "slapd slapd/purge_database boolean true" | debconf-set-selections

# (LDAP) RECONFIGURE SLAPD
echo "[LDAP] INVOKING RECONFIGURATION OF SLAPD"
dpkg-reconfigure -f noninteractive slapd
echo "[LDAP] Starting SLAPD"
/etc/init.d/slapd start

# (LDAP) INSERT ZARAFA SCHEME
echo "[LDAP] INSERTING ZARAFA SCHEME INTO LDAP"
zcat /usr/share/doc/zarafa/zarafa.ldif.gz | ldapadd -H ldapi:/// -Y EXTERNAL

# (LDAP) INSERT TEMPLATE USER
echo "[LDAP] CREATING FIRST ZARAFA USER"
ldif="/usr/local/bin/ldap.ldif"
sed -i 's/dc=REPLACE,dc=ME/'${LB_LDAP_DN}'/g' $ldif
ldapadd -x -D cn=admin,${LB_LDAP_DN} -w ${LB_LDAP_PASSWORD} -f $ldif

# (SSH) REGENERATE SSH-HOST-KEY
echo "[SSH] REGENERATING SSH HOST-KEY"
rm -v /etc/ssh/ssh_host_*
dpkg-reconfigure openssh-server
sed -i 's/^PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config

# (MYSQL) UPDATE ROOT-USER PASSWORD
echo "[MySQL] STARTING MySQL SERVER"
mysqld_safe &
echo "[MYSQL] SETTING NEW ROOT PASSWORD"
sleep 10s && mysqladmin -u root password ${LB_MYSQL_PASSWORD}
mysqlcheck --all-databases -uroot -p${LB_MYSQL_PASSWORD}

# (AMAVIS) SET DOMAIN NAME
echo "[AMAVIS] SETTING DOMAIN NAME"
sed -i 's/^\#$myhostname.*/\$myhostname = \"'${HOSTNAME}'.'${LB_MAILDOMAIN}'\";/g' /etc/amavis/conf.d/05-node_id

# (AMAVIS) ADD USER
echo "[AMAVIS] Adding user 'clamav' to group 'amavis'"
adduser clamav amavis

# (SPAMASSASSIN) Enable
echo "[SPAMASSASSIN] Enabling Spamassassin and daily Cronjob"

sed -i 's/^ENABLED=0/ENABLED=1/g' /etc/default/spamassassin
sed -i 's/^CRON=0/CRON=1/g' /etc/default/spamassassin

# (POSTFIX) SET CONFIGURATION VALUES
echo "[POSTFIX] REPLACING CONFIGURATION VALUES"

echo ${HOSTNAME}.${LB_MAILNAME} > /etc/mailname

pf="/etc/postfix/main.cf"
pfs="/etc/postfix/saslpass"

sed -i 's/^virtual_mailbox_domains.*/virtual_mailbox_domains = '${LB_MAILDOMAIN}'/g' $pf
sed -i 's/^myhostname.*/myhostname = '${HOSTNAME}'/g' $pf
sed -i 's/^mydestination.*/mydestination = localhost, '${HOSTNAME}'/g' $pf
sed -i 's/^realyhost.*/relayhost = '${EBIS_RELAYHOST}'/g' $pf

echo "${LB_RELAYHOST} ${LB_RELAYHOST_USERNAME}:${LB_RELAYHOST_PASSWORD}" > $pfs
postmap $pfs

sed -i 's/^search_base.*/search_base = ou=Zarafa,'${LB_LDAP_DN}'/g' /etc/postfix/ldap-users.cf
sed -i 's/^search_base.*/search_base = ou=Zarafa,'${LB_LDAP_DN}'/g' /etc/postfix/ldap-aliases.cf

# (ZARAFA) REPLACING LDAP SETTINGS
echo "[ZARAFA] REPLACING LDAP SETTINGS"
mv /etc/zarafa/ldap.openldap.cfg /etc/zarafa/ldap.cfg
sed -i 's/^ldap_search_base.*/ldap_search_base = ou=Zarafa,'${LB_LDAP_DN}'/g' /etc/zarafa/ldap.cfg
sed -i 's/^ldap_bind_user.*/ldap_bind_user = cn=admin,'${LB_LDAP_DN}'/g' /etc/zarafa/ldap.cfg
sed -i 's/^user_plugin.*/user_plugin = ldap/g' /etc/zarafa/server.cfg

# (ZARAFA) REPLACING MYSQL & LDAP PASSWORD
echo "[ZARAFA] REPLACING MYSQL PASSWORD"
sed -i 's/^mysql_password.*/mysql_password = '${LB_MYSQL_PASSWORD}'/g' /etc/zarafa/server.cfg
sed -i 's/^ldap_bind_passwd.*/ldap_bind_passwd = '${LB_LDAP_PASSWORD}'/g' /etc/zarafa/ldap.cfg

# (ZARAFA) Setup external MySQL-Server
if [[ ${LB_EXT_MYSQL} == "yes" ]]; then
    echo "[ZARAFA] Setting up external MySQL-Server"
    sed -i 's/^mysql_host.*/mysql_host = '${LB_EXT_MYSQL_SERVER}'/g' /etc/zarafa/server.cfg
    sed -i 's/^mysql_port.*/mysql_port = '${LB_EXT_MYSQL_PORT}'/g' /etc/zarafa/server.cfg
    sed -i 's/^mysql_database.*/mysql_database = '${LB_EXT_MYSQL_DB}'/g' /etc/zarafa/server.cfg
    sed -i 's/^mysql_user.*/mysql_user = '${LB_EXT_MYSQL_USER}'/g' /etc/zarafa/server.cfg

    echo "[MYSQL] Removing pre-installed MySQL-Server"
    apt-get remove --purge mysql-server mysql-client mysql-common
    apt-get autoremove
    apt-get autoclean
    deluser mysql
    delgroup mysql
    rm -rf /var/lib/mysql

fi

# (ZARAFA) INSERTING ZARAFA LICENSE
echo "[ZARAFA] INSERTING LICENSE"
echo ${LB_ZARAFA_LICENSE} > /etc/zarafa/license/base

# (FETCHMAIL) Add fetchmailrc and Cronjob
echo "[FETCHMAIL] Adding fetchmailrc and cronjob"
touch /etc/fetchmailrc
chmod 0700 /etc/fetchmailrc && chown postfix /etc/fetchmailrc
cronline="*/5 * * * * su postfix -c '/usr/bin/fetchmail -f /etc/fetchmailrc'"
(crontab -u root -l; echo "${cronline}" ) | crontab -u root -

# (Z-PUSH) Download and install Z-Push
echo "[Z-PUSH] Downloading and installing Z-Push"
curl http://download.z-push.org/final/2.1/z-push-2.1.3-1892.tar.gz | tar -xz -C /usr/share/
mv /usr/share/z-push-* /usr/share/z-push
mkdir /var/lib/z-push /var/log/z-push
chmod 755 /var/lib/z-push /var/log/z-push
chown www-data:www-data /var/lib/z-push /var/log/z-push
ln -s /usr/share/z-push/z-push-admin.php /usr/sbin/z-push-admin
ln -s /usr/share/z-push/z-push-top.php /usr/sbin/z-push-top

# (APACHE) Enable PhpLDAPadmin, Zarafa Webaccess/Webapp and Z-Push
mv /etc/apache2/sites-available/zarafa-webaccess /etc/apache2/sites-available/zarafa-webaccess.conf
mv /etc/apache2/sites-available/zarafa-webapp /etc/apache2/sites-available/zarafa-webapp.conf
cp /etc/phpldapadmin/apache.conf /etc/apache2/sites-available/phpldapadmin.conf

a2ensite zarafa-webaccess
a2ensite zarafa-webapp
a2ensite phpldapadmin
a2ensite z-push

# (APACHE) Put zarafaclient into /var/www/html
echo > /var/www/html/index.html
mv /root/windows/zarafaclient* /var/www/html/zarafaclient.msi

# (PHPLDAPADMIN) Edit config.php
echo "[PHPLDAPADMIN] Editing config.php"
sed -i 's/dc=example,dc=com/'${LB_LDAP_DN}'/g' /etc/phpldapadmin/config.php

# (SYSTEM) SET ROOT PASSWORD
echo "[SYSTEM] SETTING NEW ROOT PASSWORD"
echo "root:${LB_ROOT_PASSWORD}" | chpasswd

# (Clamav) Refreshing Clamav database
echo "[Clamav] Refreshing Clamav database (be patient ...)"
freshclam --stdout

# FINISHED
echo ""
echo "SETUP FINISHED!"
echo ""
export FIRSTRUN=no
