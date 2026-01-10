#!/bin/bash
set -e

echo "=== Starting MongoDB installation ==="
export DEBIAN_FRONTEND=noninteractive

# Import MongoDB GPG Key
echo "Adding MongoDB GPG key..."
wget -qO - https://www.mongodb.org/static/pgp/server-6.0.asc | sudo gpg --dearmor -o /usr/share/keyrings/mongodb-server-6.0.gpg

# Add MongoDB Repository
echo "Adding MongoDB repository..."
echo "deb [ signed-by=/usr/share/keyrings/mongodb-server-6.0.gpg ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/6.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-6.0.list

# Update and install MongoDB
echo "Installing MongoDB..."
sudo apt-get update -qq
sudo apt-get install -y mongodb-org

# Start MongoDB
echo "Starting MongoDB..."
sudo systemctl start mongod
sudo systemctl enable mongod
sleep 3

# Configure MongoDB
echo "Configuring MongoDB..."
MONGO_CONF="/etc/mongod.conf"
sudo sed -i 's/bindIp: 127.0.0.1/bindIp: 0.0.0.0/' $MONGO_CONF

# Restart MongoDB
sudo systemctl restart mongod
sleep 3

# Create admin user
echo "Creating admin user..."
mongosh --eval 'db.getSiblingDB("admin").createUser({user: "admin", pwd: "admin", roles: [{role: "root", db: "admin"}]})' || \
mongo --eval 'db.getSiblingDB("admin").createUser({user: "admin", pwd: "admin", roles: [{role: "root", db: "admin"}]})'

# Enable authentication
echo "Enabling authentication..."
if ! grep -q "^security:" $MONGO_CONF; then
  echo -e "\nsecurity:\n  authorization: enabled" | sudo tee -a $MONGO_CONF
fi

# Final restart
sudo systemctl restart mongod
sleep 3

echo "=== MongoDB installation complete ==="

# Install AWS CLI v2
echo "=== Installing AWS CLI ==="
cd /tmp
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
sudo apt-get install -y -qq unzip
unzip -q awscliv2.zip
sudo ./aws/install --update 2>/dev/null || sudo ./aws/install
rm -rf awscliv2.zip aws/
aws --version

# Install kubectl, helm, docker (non-blocking)
echo "=== Installing kubectl, helm, docker ==="
sudo snap install kubectl --classic 2>/dev/null || true
sudo snap install helm --classic 2>/dev/null || true
sudo snap install docker 2>/dev/null || true

echo "=== All installations complete! ==="
