# Initialization and Setup for a new
# created Docker Container
#
# Modified by: azmodan2k <work@azmodan.com>
# Original Author: Tobias Mandjik <webmaster@leckerbeef.de>
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

########
# LDAP #
########

    # Delete old Database (if some may exist)
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    echo "[LDAP] DELETING OLD DATABASES"
    rm -rf /var/lib/ldap/*

    # Set Values for reconfiguration of SLAPD
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    echo "[LDAP] SETTING NEW CONFIGURATION VALUES"
    echo "slapd slapd/password1 password ${LB_LDAP_PASSWORD}" | debconf-set-selections
    echo "slapd slapd/password2 password ${LB_LDAP_PASSWORD}" | debconf-set-selections
    echo "slapd slapd/internal/adminpw password ${LB_LDAP_PASSWORD}" | debconf-set-selections
    echo "slapd slapd/internal/generated_adminpw password ${LB_LDAP_PASSWORD}" | debconf-set-selections
    echo "slapd slapd/allow_ldap_v2 boolean false" | debconf-set-selections
    echo "slapd slapd/invalid_config boolean true" | debconf-set-selections
    echo "slapd slapd/move_old_database boolean false" | debconf-set-selections
    echo "slapd slapd/backend select HDB" | debconf-set-selections
    echo "slapd shared/organization string ${LB_LDAP_DN}" | debconf-set-selections
    echo "slapd slapd/domain string ${LB_MAILDOMAIN}" | debconf-set-selections
    echo "slapd slapd/no_configuration boolean false" | debconf-set-selections
    echo "slapd slapd/dump_database_destdir string /var/backups/slapd-VERSION" | debconf-set-selections
    echo "slapd slapd/purge_database boolean true" | debconf-set-selections

    # Now reconfigure and start SLAPD
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    echo "[LDAP] INVOKING RECONFIGURATION OF SLAPD"
    dpkg-reconfigure -f noninteractive slapd

    echo "[LDAP] Starting SLAPD"
    /etc/init.d/slapd start

    # Insert new Schemas and template-User
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    echo "[LDAP] INSERTING FETCHMAIL SCHEME INTO LDAP"
    ldapadd -H ldapi:/// -Y EXTERNAL -f /etc/ldap/schema/fetchmail.ldif

    echo "[LDAP] INSERTING ZARAFA SCHEME INTO LDAP"
    zcat /usr/share/doc/zarafa/zarafa.ldif.gz | ldapadd -H ldapi:/// -Y EXTERNAL

    echo "[LDAP] CREATING TEMPLATE ZARAFA USER"
    sed -i -e 's/dc=REPLACE,dc=ME/'${LB_LDAP_DN}'/g' /usr/local/bin/ldap.ldif
    ldapadd -H ldapi:/// -x -D cn=admin,${LB_LDAP_DN} -w ${LB_LDAP_PASSWORD} -f /usr/local/bin/ldap.ldif

#######
# SSH #
#######

    # Regenerate SSH Host-Key
    # ~~~~~~~~~~~~~~~~~~~~~~~

    echo "[SSH] REGENERATING SSH HOST-KEY"
    rm -v /etc/ssh/ssh_host_*
    dpkg-reconfigure openssh-server
    sed -i -e 's/^PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config

#######
# SSL #
#######

    # the magic will happen in a
    # seperate bash script
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~

    /usr/local/bin/ssl-cert.sh

#########
# MySQL #
#########

    # Update Password of user "root"
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    echo "[MySQL] STARTING MySQL SERVER"
    service mysql start && sleep 15s

    echo "[MYSQL] SETTING NEW ROOT PASSWORD"
    mysqladmin -u root password ${LB_MYSQL_PASSWORD}
    mysqlcheck --all-databases -uroot -p${LB_MYSQL_PASSWORD}

##########
# AMAVIS #
##########

    # Set Hostname and add user 'clamav'
    # to group of 'amavis'
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    echo "[AMAVIS] SETTING HOSTNAME"
    sed -i -e 's/^\#$myhostname.*/\$myhostname = \"'${HOSTNAME}'.'${LB_MAILDOMAIN}'\";/g' /etc/amavis/conf.d/05-node_id

    echo "[AMAVIS] ADDING USER 'clamav' TO GROUP 'amavis'"
    adduser clamav amavis

################
# SPAMASSASSIN #
################

    # Enable Spamassassin and daily Cronjob
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    echo "[SPAMASSASSIN] Enabling Spamassassin and daily Cronjob"
    sed -i -e 's/^ENABLED=0/ENABLED=1/g' -e 's/^CRON=0/CRON=1/g' /etc/default/spamassassin

############
# SASLAUTH #
############

	echo "[SASLAUTH] EDIT SASLAUTH CONNECTION FILE"
    sed -i -e 's/dc=REPLACE,dc=ME/'${LB_LDAP_DN}'/g' /etc/saslauthd.conf
	
###########
# POSTFIX #
###########

    # Setting Mailname
    # ~~~~~~~~~~~~~~~~

    echo "[POSTFIX] REPLACING CONFIGURATION VALUES"
    echo ${HOSTNAME}.${LB_MAILNAME} > /etc/mailname

    # Replace and set configuration Values
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    sed -i -e 's/^virtual_mailbox_domains.*/virtual_mailbox_domains = '${LB_MAILDOMAIN}'/g' \
           -e 's/^myhostname.*/myhostname = '${HOSTNAME}'/g' \
           -e 's/^mydestination.*/mydestination = localhost, '${HOSTNAME}'/g' \
           -e 's/^realyhost.*/relayhost = '${LB_RELAYHOST}'/g' \
           /etc/postfix/main.cf

    # Generating File for SASL-Authentication
    # of the Relayhost
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    echo "${LB_RELAYHOST} ${LB_RELAYHOST_USERNAME}:${LB_RELAYHOST_PASSWORD}" > /etc/postfix/saslpass
    postmap /etc/postfix/saslpass

    # Replacing search base to lookup
    # users and aliases in LDAP
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    sed -i -e 's/^search_base.*/search_base = ou=Zarafa,'${LB_LDAP_DN}'/g' /etc/postfix/ldap-users.cf
    sed -i -e 's/^search_base.*/search_base = ou=Zarafa,'${LB_LDAP_DN}'/g' /etc/postfix/ldap-aliases.cf

##########
# ZARAFA #
##########

    # Setting up LDAP configuration file
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    echo "[ZARAFA] REPLACING LDAP/MYSQL SETTINGS"
    mv /etc/zarafa/ldap.openldap.cfg /etc/zarafa/ldap.cfg

    sed -i -e 's/^ldap_search_base.*/ldap_search_base = ou=Zarafa,'${LB_LDAP_DN}'/g' \
           -e 's/^ldap_bind_user.*/ldap_bind_user = cn=admin,'${LB_LDAP_DN}'/g' \
           -e 's/^ldap_bind_passwd.*/ldap_bind_passwd = '${LB_LDAP_PASSWORD}'/g' \
           /etc/zarafa/ldap.cfg

    zarafapass=$(cat /etc/ssl/zarafa/zarafa.pass)
    sed -i -e 's/^user_plugin.*/user_plugin = ldap/g' \
           -e 's/^mysql_password.*/mysql_password = '${LB_MYSQL_PASSWORD}'/g' \
           -e 's/^server_ssl_enabled.*/server_ssl_enabled = yes/g' \
           -e 's/^server_ssl_key_file.*/server_ssl_key_file = \/etc\/ssl\/zarafa\/zarafaserver.pem/g' \
           -e 's/^server_ssl_key_pass.*/server_ssl_key_pass = '${zarafapass}'/g' \
           -e 's/^server_ssl_ca_file.*/server_ssl_ca_file = \/etc\/ssl\/zarafa\/ca.crt/g' \
           /etc/zarafa/server.cfg

    # Additional setup for external MySQL-Server
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    if [[ ${LB_EXT_MYSQL} == "yes" ]]; then
        echo "[ZARAFA] Setting up external MySQL-Server"
        sed -i -e 's/^mysql_host.*/mysql_host = '${LB_EXT_MYSQL_SERVER}'/g' \
               -e 's/^mysql_port.*/mysql_port = '${LB_EXT_MYSQL_PORT}'/g' \
               -e 's/^mysql_database.*/mysql_database = '${LB_EXT_MYSQL_DB}'/g' \
               -e 's/^mysql_user.*/mysql_user = '${LB_EXT_MYSQL_USER}'/g' \
               /etc/zarafa/server.cfg

        # Remove previously installed MySQL-Server
        # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

        echo "[MYSQL] Removing pre-installed MySQL-Server"
        apt-get remove --purge mysql-server mysql-client mysql-common
        apt-get autoremove
        apt-get autoclean
        deluser mysql
        delgroup mysql
        rm -rf /var/lib/mysql

    fi

    # Inserting Zarafa License
    # ~~~~~~~~~~~~~~~~~~~~~~~~

    echo "[ZARAFA] INSERTING LICENSE"
    echo ${LB_ZARAFA_LICENSE} > /etc/zarafa/license/base

##########
# Z-PUSH #
##########

    # Download and install Z-Push
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~

    echo "[Z-PUSH] Downloading and installing Z-Push"
    curl http://download.z-push.org/final/2.2/z-push-2.2.8.tar.gz | tar -xz -C /usr/share/

    mv /usr/share/z-push-* /usr/share/z-push
    mkdir /var/lib/z-push /var/log/z-push

    # Setup Filepermissions and Owner
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    chmod 755 /var/lib/z-push /var/log/z-push
    chown www-data:www-data /var/lib/z-push /var/log/z-push

    # Link Z-Push-Admin and Z-Push-Top
    # to call the commands directly
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    ln -s /usr/share/z-push/z-push-admin.php /usr/sbin/z-push-admin
    ln -s /usr/share/z-push/z-push-top.php /usr/sbin/z-push-top

#############
# FETCHMAIL #
#############

    # Adding Fetchmail to Cron
    # ~~~~~~~~~~~~~~~~~~~~~~~~

    echo "[FETCHMAIL] Adding fetchmail to cronjob"
    sed -i -e 's/^BASE_DN.*/BASE_DN='${LB_LDAP_DN}'/g' /usr/local/bin/fetchmail.sh

    cronline="*/5 * * * * /usr/local/bin/fetchmail.sh | /usr/bin/fetchmail -f -"
    (crontab -u root -l; echo "${cronline}") | crontab -u root -

##########
# APACHE #
##########

    # Renaming Sites
    # ~~~~~~~~~~~~~~

    echo "[APACHE] ENABLING SITES AND 'mod_rewrite'"
    #mv /etc/apache2/sites-available/zarafa-webaccess /etc/apache2/sites-available/zarafa-webaccess.conf
    #mv /etc/apache2/sites-available/zarafa-webapp /etc/apache2/sites-available/zarafa-webapp.conf
    #cp /etc/phpldapadmin/apache.conf /etc/apache2/sites-available/phpldapadmin.conf

	# Enable SSL-Support
    # ~~~~~~~~~~~~~~~~~~
    echo "[APACHE] Enabling SSL-Suport"
    a2enmod ssl
    a2ensite default-ssl.conf

	
    # Enabling PhpLDAPadmin, Zarafa Webaccess/Webapp and Z-Push
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
	a2enmod rewrite
	
    a2ensite zarafa-webapp
	a2ensite z-push
    a2ensite phpldapadmin
        
    # Make index.html empty and put Zarafaclient
    # into /var/www
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    echo "" > /var/www/html/index.html
    #mv /root/windows/zarafaclient* /var/www/html/zarafaclient.msi

################
# PHPLADPADMIN #
################

    # Replacing some values of config.php
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    echo "[PHPLDAPADMIN] Editing config.php"
    sed -i -e 's/dc=example,dc=com/'${LB_LDAP_DN}'/g' \
           -e '/hide_template_warning/s/^\/\/ //g' \
           /etc/phpldapadmin/config.php

##########
# SYSTEM #
##########

    # Change 'root' password
    # ~~~~~~~~~~~~~~~~~~~~~~

    echo "[SYSTEM] SETTING NEW ROOT PASSWORD"
    echo "root:${LB_ROOT_PASSWORD}" | chpasswd

##########
# Clamav #
##########

    # Refreshing Clamav-Database with freshclam
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    echo "[Clamav] Refreshing Clamav database (be patient ...)"
    #freshclam --stdout

############
# FINISHED #
############

    # Set 'firstrun' value
    # ~~~~~~~~~~~~~~~~~~~~

    echo "no" > /usr/local/bin/firstrun

    echo ""
    echo "SETUP FINISHED!"
    echo ""
