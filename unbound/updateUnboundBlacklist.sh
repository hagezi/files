#!/bin/bash

# Variables
url=https://raw.githubusercontent.com/hagezi/dns-blocklists/main/unbound # Blacklist repository
confdir=/etc/unbound/unbound.conf.d                                      # Unbound config dir
blacklist=pro.blacklist.conf                                             # Blacklist file

# Get Blacklist
echo "# Download Blacklist ..."
echo ""
sudo wget -O $confdir/$blacklist $url/$blacklist

# Restart Unbound service
echo -n "# Reload Unbound config: "
sudo service unbound reload
echo "done"
echo ""

# Check Unbound Ccnfig
sudo unbound-checkconf
echo ""

# Print Unbound Service status
sudo service unbound status
echo ""

exit
