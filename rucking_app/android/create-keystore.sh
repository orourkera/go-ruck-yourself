#!/bin/bash

# Path to save the keystore
KEYSTORE_PATH="../keystore.jks"
KEY_ALIAS="upload"
KEYSTORE_PASSWORD="getruckypassword123"
KEY_PASSWORD="getruckypassword123"

# Create directory if it doesn't exist
cd "$(dirname "$0")"

# Generate keystore
keytool -genkey -v \
        -keystore keystore.jks \
        -keyalg RSA \
        -keysize 2048 \
        -validity 10000 \
        -alias $KEY_ALIAS \
        -storepass $KEYSTORE_PASSWORD \
        -keypass $KEY_PASSWORD \
        -dname "CN=GetRuck, OU=Mobile, O=GetRuck Inc., L=San Francisco, ST=California, C=US"

# Display the fingerprints
echo "Keystore created at $(pwd)/keystore.jks"
echo "Displaying fingerprints:"
keytool -list -v -keystore keystore.jks -alias $KEY_ALIAS -storepass $KEYSTORE_PASSWORD

# Remind to use environment variables
echo ""
echo "Remember to set these environment variables when building:"
echo "export KEYSTORE_PASSWORD=\"$KEYSTORE_PASSWORD\""
echo "export KEY_PASSWORD=\"$KEY_PASSWORD\""
