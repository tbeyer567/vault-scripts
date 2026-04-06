#!/bin/bash

set -eu

VAULT_VERSION="1.11.4+ent-1"
VAULT_BINARY_LOCATION=/home/user123/vault
VAULT_LICENSE_KEY="lskdjaflwekajlr3lwkrj23lja<UPDATE>"
VAULT_USER="vault"
VAULT_GROUP="vault"
#ALL CERTIFICATES SHOULD BE BASE64
#Concatenate for full chain
CERTIFICATE_FILE=/path/to/vault.crt
CERTIFICATE_KEY=/path/to/vault.key
CLIENT_CA_FILE=/path/to/ca.pem
FULL_HOSTNAME="$(hostname -f)"
HOSTNAME="$(hostname)"
DOMAIN_NAME=$(hostname -d)
HOST_IP="$(hostname -I|xargs)"
OTHER_ADDR="Other"
declare -a NODE_NAMES=("asdNode1" "asdNode2" "asdNode3" "asdNode4")


echo "Hostname is $FULL_HOSTNAME, do you want to continue with this? If not this will be set to $HOST_IP (y/n)" 
select input in $FULL_HOSTNAME $HOST_IP $OTHER_ADDR
do
    case $input in 
        $FULL_HOSTNAME)
            echo "Continuing with ${FULL_HOSTNAME}"
            break
            ;;
        $HOST_IP)
            echo "Continuing with ${HOST_IP}"
            FULL_HOSTNAME=$HOST_IP
            break
            ;;
        $OTHER_ADDR)
            read -p "Enter Vault ADDR you would like to use for this host: " OTHER_ADDR
            FULL_HOSTNAME=$OTHER_ADDR
            break
            ;;
    esac
done


if ! id -u $VAULT_USER > /dev/null 2>&1; then
        useradd \
                --system \
                --user-group \
                --shell /bin/false \
                --comment "${VAULT_USER} service account" \
                $VAULT_USER
fi


#Create Service File /usr/lib/systemd/system/vault.service
echo "Writing Vault Service File /usr/lib/systemd/system/vault.service" 
sudo cat << EOF > /usr/lib/systemd/system/vault.service
[Unit]
Description="HashiCorp Vault - A tool for managing secrets"
Documentation=https://www.vaultproject.io/docs/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/etc/vault.d/vault.hcl
StartLimitIntervalSec=60
StartLimitBurst=3

[Service]
Type=notify
EnvironmentFile=/etc/vault.d/vault.env
User=${VAULT_USER}
Group=${VAULT_GROUP}
ProtectSystem=full
ProtectHome=read-only
PrivateTmp=yes
PrivateDevices=yes
SecureBits=keep-caps
AmbientCapabilities=CAP_IPC_LOCK
CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK
NoNewPrivileges=yes
ExecStart=/usr/bin/vault server -config=/etc/vault.d/vault.hcl
ExecReload=/bin/kill --signal HUP \$MAINPID
KillMode=process
KillSignal=SIGINT
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
LimitNOFILE=65536
LimitMEMLOCK=infinity

[Install]
WantedBy=multi-user.target
EOF

chmod 0644 /usr/lib/systemd/system/vault.service
chown root:root /usr/lib/systemd/system/vault.service

#Make directory for Vault, permissions are fixed below
mkdir --parents /etc/vault.d/

mkdir --parents /opt/vault
mkdir --parents /opt/vault/snapshots
mkdir --parents /opt/vault/license
# Create TLS and Data directory
mkdir --parents /opt/vault/tls
mkdir --parents /opt/vault/data

#Creating /etc/vault.d/vault.env
echo "Creating /etc/vault.d/vault.env"
touch /etc/vault.d/vault.env

#Copy Vault Binary to bin
cp $VAULT_BINARY_LOCATION /usr/bin/vault
chown root:root /usr/bin/vault
chmod 755 /usr/bin/vault

#Create License File /opt/vault/license/vault.hclic
echo "Writing License File /opt/vault/license/vault.hclic"
sudo cat << EOF > /opt/vault/license/vault.hclic
$VAULT_LICENSE_KEY
EOF

##Certificate Stuff
#if [[ -f /opt/vault/tls/tls.crt ]] && [[ -f /opt/vault/tls/tls.key ]]; then
#  echo "Vault TLS key and certificate already exist. Exiting."
#  exit 0
#fi
if [ -z ${NODE_NAMES+x} ]; then 
    echo "No Peers Set (Variable NODE_NAMES)";
    RAFT_BUILD="" 
else 
    for xnode in ${NODE_NAMES[@]}
        do
        RAFT_BUILD+=$'    retry_join {\n'
        RAFT_BUILD+=$'        leader_api_addr = "https://'${xnode}.${DOMAIN_NAME}':8200"'
        RAFT_BUILD+=$'\n    }\n'
    done
fi

#Write the Vault Configuration File /etc/vault.d/vault.hcl
echo "Writing the Configuration file /etc/vault.d/vault.hcl"
sudo cat << EOF > /etc/vault.d/vault.hcl
listener "tcp" {
  address                  = "0.0.0.0:8200"
  tls_cert_file            = "/opt/vault/tls/vault.crt"
  tls_key_file             = "/opt/vault/tls/vault.key"
  tls_disable_client_certs = false
  tls_disable              = false
}


seal "shamir" {
}

storage "raft" {
  path    = "/opt/vault/data"
  node_id = "${FULL_HOSTNAME}"
${RAFT_BUILD}
}

license_path = "/opt/vault/license/vault.hclic"

disable_mlock = true
log_level   = "ERROR"

api_addr      = "https://$FULL_HOSTNAME:8200"
cluster_addr  = "https://$FULL_HOSTNAME:8201"
ui            = true

EOF


if [[ -f $CERTIFICATE_FILE ]]; then
    cp $CERTIFICATE_FILE /opt/vault/tls/vault.crt
else
    echo "Generating Vault TLS key and self-signed certificate..."
# Generate TLS key and certificate
    cd /opt/vault/tls
    openssl req \
      -out tls.crt \
      -new \
      -keyout tls.key \
      -newkey rsa:4096 \
      -nodes \
      -sha256 \
      -x509 \
      -subj "/O=HashiCorp/CN=Vault" \
      -days 1095 # 3 years

    mv /opt/vault/tls/tls.crt /opt/vault/tls/vault.crt
    mv /opt/vault/tls/tls.key /opt/vault/tls/vault.key
fi

if [[ -f $CERTIFICATE_KEY ]]; then
    cp $CERTIFICATE_KEY /opt/vault/tls/vault.key
else
    echo "No Key Found for Certificate"
fi

# Update file permissions
chown --recursive "${VAULT_USER}:${VAULT_GROUP}" /etc/vault.d
chown --recursive "${VAULT_USER}:${VAULT_GROUP}" /opt/vault
chmod 0600 /opt/vault/tls/vault.crt /opt/vault/tls/vault.key
chmod 0700 /opt/vault/tls
chmod 0700 /etc/vault.d

echo "Vault TLS key and self-signed certificate have been generated in '/opt/vault/tls'."

# Set IPC_LOCK capabilities on vault
setcap cap_ipc_lock=+ep /usr/bin/vault

if [ -d /run/systemd/system ]; then
    systemctl --system daemon-reload >/dev/null || true
fi

if [[ $(vault version) == *+ent* ]]; then
echo "
The following shall apply unless your organization has a separately signed Enterprise License Agreement or Evaluation Agreement governing your use of the software: 
Software in this repository is subject to the license terms located in the software, copies of which are also available at https://eula.hashicorp.com/ClickThruELA-Global.pdf or https://www.hashicorp.com/terms-of-evaluation 
as applicable. Please read the license terms prior to using the software. Your installation and use of the software constitutes your acceptance of these terms. If you do not accept the terms, do not use the software.
"
fi