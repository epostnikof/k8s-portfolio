#!/bin/bash

# Проверка количества аргументов
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <domain_name> <expiry_days>"
    exit 1
fi

domain_name="$1"
expiry_days="$2"
secret_name=$(echo "$domain_name" | tr . -)-tls
yaml_file="$secret_name.yaml"

# Удаление старых ключей и YAML файла, если они существуют
if [ -f "$domain_name.key" ]; then
    rm "$domain_name.key"
fi
if [ -f "$domain_name.crt" ]; then
    rm "$domain_name.crt"
fi
if [ -f "$yaml_file" ]; then
    rm "$yaml_file"
fi

# Создание SSL сертификата
openssl req -x509 -newkey rsa:4096 -keyout "$domain_name.key" -out "$domain_name.crt" \
    -sha256 -days "$expiry_days" -nodes \
    -subj "/CN=$domain_name/O=Universe/OU=Saint-Petersburg" \
    -addext "subjectAltName=DNS:$domain_name,DNS:www.$domain_name"

# Создание Kubernetes Secret и сохранение в файл YAML
kubectl create secret tls "$secret_name" \
    --cert "$domain_name.crt" \
    --key "$domain_name.key" \
    --dry-run=client -o yaml > "$yaml_file"

echo "Secret YAML file created: $yaml_file"
