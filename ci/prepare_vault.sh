#!/bin/bash

# Принимаем переданные переменные
VAULT_ROOT_TOKEN=$1
VAULT_USEAL_KEY_1=$2
VAULT_USEAL_KEY_2=$3
VAULT_USEAL_KEY_3=$4
shift 2
PODS=("$@")

# Выполняем Unseal для всех pod Vault, если они Sealed
# Также добавляем некоторые настроки авторизации,
# которые сбрасываются при перезапуске Vault
for POD in "${PODS[@]}"; do
	SEALED=$(kubectl -n vault exec $POD -- vault status 2>&1 | grep '^Sealed' | awk '{print $2}')
	if [ "$SEALED" = "true" ]; then
		echo "Unsealing $POD..."
		kubectl -n vault exec $POD -- vault operator unseal "$VAULT_USEAL_KEY_1"
		kubectl -n vault exec $POD -- vault operator unseal "$VAULT_USEAL_KEY_2"
		kubectl -n vault exec $POD -- vault operator unseal "$VAULT_USEAL_KEY_3"
	else
		echo "$POD is already unsealed."
	fi
done

# Выполняем настройку авторизации Kubernetes в Vault
kubectl -n vault exec vault-0 -- /bin/sh -c "
      vault login "$VAULT_ROOT_TOKEN" && \
      vault write auth/kubernetes/config \
      kubernetes_host=\"https://kubernetes.default.svc:443\" \
      token_reviewer_jwt=\"\$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)\" \
      kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
      issuer=\"https://kubernetes.default.svc.cluster.local\"
      "
