#!/bin/bash
set -euo pipefail

# Packages

dnf install -y python3.12 python3.12-pip unzip amazon-cloudwatch-agent

# App

useradd --system --no-create-home --shell /sbin/nologin expense-app

aws s3 cp "s3://${app_bucket}/${app_key}" /tmp/app.zip --region "${region}"
mkdir -p /opt/expense-app
unzip -o /tmp/app.zip -d /opt/expense-app

python3.12 -m venv /opt/expense-app/venv
/opt/expense-app/venv/bin/pip install --quiet -r /opt/expense-app/requirements.txt

cat > /etc/sysconfig/expense-app <<EOF
DB_HOST=${db_host}
DB_NAME=${db_name}
DB_SECRET_ARN=${db_secret_arn}
AWS_REGION=${region}
EOF
chmod 600 /etc/sysconfig/expense-app

cp /opt/expense-app/expense-app.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now expense-app

# Logs

cat > /etc/logrotate.d/expense-app <<EOF
/var/log/expense-app.log {
    daily
    rotate 3
    maxsize 50M
    missingok
    notifempty
    compress
    copytruncate
}
EOF

cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<EOF
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/expense-app.log",
            "log_group_name": "${log_group}",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  }
}
EOF

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
