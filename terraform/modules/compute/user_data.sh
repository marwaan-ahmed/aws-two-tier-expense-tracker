#!/bin/bash
# Placeholder page until the real app is deployed

mkdir -p /var/www
echo "Served by $(ec2-metadata -i | cut -d ' ' -f 2) in $(ec2-metadata -z | cut -d ' ' -f 2)" > /var/www/index.html
echo "ok" > /var/www/health

systemd-run --unit=placeholder -p DynamicUser=yes /usr/bin/python3 -m http.server 8000 --directory /var/www
