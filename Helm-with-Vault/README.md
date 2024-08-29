# Vault

![MDM](../images/vault.png)

## Важная информация

На данный момент поддеживается хранение секретов, которые попадают в переменные окружения контейнера. Что это значит? Мы будем помещать чувствительные данные, такие как имена, пользователей, пароли и т.п. в зашифрованное хранилище Vault, а не хранить эту информацию в открытом виде в etcd.
Однако такие секреты как SSL сертификаты или `dockerconfigjson` будут храниться по прежнему в etcd.
Стоит отметить, что `dockerconfigjson` не обязательно постоянно хранить в кластере - он нужен только для загрузки образа из приватного репозитория и его можно удалить после развёртки/обновления приложения:

```sh
kubectl get secret -n smart-etl
```

Как правило в имени такого секрета будет фигурировать `<app_name>-regcred`

Для удаления такого секрета воспользуемся командой:

```sh
kubectl delete secret -n smart-etl <app_name>-regcred
```

## Установка

### Хранилище данных

В качестве хранилища данных в Vault будем использовать PostgreSQL

В PostgreeSQL:

- Добавляем пользователя vault.
- Cоздаем базу vault и добавляем в нее таблицы.
- Предоставляем права доступа пользователю vault на базу и таблицы.

Скрипт (см. файл `create_database.sql`):

```sql
-- Создание пользователя
CREATE USER vault WITH PASSWORD 'your_password_here';

-- Создание базы данных
CREATE DATABASE vault OWNER vault;

-- Подключение к базе данных
\connect vault;

-- Создание таблиц
CREATE TABLE vault_kv_store (
  parent_path TEXT COLLATE "C" NOT NULL,
  path        TEXT COLLATE "C",
  key         TEXT COLLATE "C",
  value       BYTEA,
  CONSTRAINT pkey PRIMARY KEY (path, key)
);

CREATE INDEX parent_path_idx ON vault_kv_store (parent_path);

CREATE TABLE vault_ha_locks (
  ha_key      TEXT COLLATE "C" NOT NULL,
  ha_identity TEXT COLLATE "C" NOT NULL,
  ha_value    TEXT COLLATE "C",
  valid_until TIMESTAMP WITH TIME ZONE NOT NULL,
  CONSTRAINT ha_key PRIMARY KEY (ha_key)
);

-- Предоставление прав доступа
GRANT ALL PRIVILEGES ON DATABASE vault TO vault;
GRANT ALL PRIVILEGES ON TABLE vault_kv_store TO vault;
GRANT ALL PRIVILEGES ON TABLE vault_ha_locks TO vault;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO vault;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO vault;
```

`your_password_here` - замените на свой пароль

Передадим скрипт

```sh
psql -h 10.21.0.33 -U <username> -d postgres -f create_database.sql
```

### values file

Откройте для редактирования файл `custom_vault_values.yaml`

Разберем по блокам:

#### Injector

```yaml
injector:
  enabled: false
```

В контексте HashiCorp Vault, "[[injector]]" (инжектор) обычно относится к компоненту или механизму, который автоматически вводит (или "инжектирует") секреты (пароли, токены, ключи и другие конфиденциальные данные) в приложение или среду. Он нам НЕ потребуется

#### Server

```yaml
server:
  image:
    repository: "hashicorp/vault"
    tag: "1.8.4"
    pullPolicy: IfNotPresent
  logLevel: "info"
  logFormat: "json"
  resources:
    requests:
      memory: 256Mi
      cpu: 250m
    limits:
      memory: 256Mi
      cpu: 250m
#  priorityClassName: "medium-priority" # если они определены в кластере
```

Основные настройки сервера, которые не нуждаются в подробном объяснении.

#### Data storage и режим работы Vault

```yaml
dataStorage:
  enabled: false
dev:
  enabled: false
standalone:
  enabled: false
ha:
  enabled: true
  replicas: 2

  # Set the api_addr configuration for Vault HA
  # See https://www.vaultproject.io/docs/configuration#api_addr
  # If set to null, this will be set to the Pod IP Address
  apiAddr: null
```

1. Мы не используем внутреннее хранилище
2. Используем Vault в режиме high available. Количество реплик - 2.

- Запускаются несколько экзепляров HashiCorp Vault, они между собой взаимодействуют
- Запечатывать и распечатывать придётся каждую реплику.

#### config

```yaml
config: |
  ui = true

  listener "tcp" {
    tls_disable = 1
    address = "[::]:8200"
    cluster_address = "[::]:8201"
  }

  storage "postgresql" {
    connection_url = "postgres://vault:password@base-pgbouncer.pgo.svc:5433/vault?sslmode=disable"
    ha_enabled = true
  }

  service_registration "kubernetes" {}
```

- Здесь выбираем хранилище для работы. То есть хранилище, где будут хранится values приложения.
- Если не переопределить этот блок, то по умолчанию будет ставится Consul.
  `connection_url = "postgres://vault:password@base-pgbouncer.pgo.svc:5432/vault?sslmode=disable"` - необходимо указать URL до базы данных postgreSQL, которую создали ранее.

#### csi

```yaml
csi:
  enabled: true
  resources:
    requests:
      cpu: 50m
      memory: 128Mi
    limits:
      cpu: 50m
      memory: 128Mi
```

Здесь указываем csi драйвер и ресурсы к нему.
На самом деле это будет ещё один pod, который просто позволяет нам работать с csi драйвером.

### Создание secret

Авторизуйтесь с пощью команды `docker login` на приватном репозитории:

```sh
docker login docker.universe-data.ru -u <username_here> -p <password_here>
```

Создайте secret в namespace vault для доступа к контейнерам из приватного репозитория:

```sh
kubectl create namespace vault &&  kubectl create secret generic my-regcred \
    --from-file=.dockerconfigjson=/home/epostnikof/.docker/config.json \
    --type=kubernetes.io/dockerconfigjson -o yaml -n vault

```

Откройте ещё раз для редактирования файл `custom_vault_values.yaml` и убедитесь, что в блоке `imagePullSecrets: my-regcred` находится название вашего secret

### Установка Helm чарта с Vault

```
helm install --namespace vault vault ./vault -f custom_vault_values.yaml
```

## Secrets store CSI driver

Потребуется для подключения сикретов из vault в init контейнеры.

### helm install

```sh
helm install --namespace vault csi ./secrets-store-csi-driver
```

> # Важно
>
> Поды с Vault сразу не запустятся. **Vault** мы пока только установили, но ещё не настроили. Это предстоит сделать далее.

```
❯ kubectl -n vault get pods
NAME                                 READY   STATUS    RESTARTS       AGE
csi-secrets-store-csi-driver-5h2jj   3/3     Running   1 (159m ago)   160m
csi-secrets-store-csi-driver-cbwhs   3/3     Running   1 (159m ago)   160m
csi-secrets-store-csi-driver-lrvgr   3/3     Running   1 (159m ago)   160m
vault-0                              0/1     Running   0              3h
vault-1                              0/1     Running   0              3h
vault-csi-provider-ks8hw             2/2     Running   0              3h
vault-csi-provider-p5wwg             2/2     Running   0              3h
vault-csi-provider-wl75p             2/2     Running   0              3h

```

Конечно, я проверю и исправлю вашу инструкцию по настройке Vault.

## Первичная настройка Vault

    kubectl -n vault get pods

Будем работать внутри подов Vault

Работаем в командной строке пода `vault-0`.

Смотрим статус Vault:

```sh
kubectl -n vault exec vault-0 -- vault status
```

Обратим внимание на следующие строчки в выводе:

```sh
Initialized        false
Sealed             true
```

Эти строки говорят о том, что Vault запечатан. Это значит, что Vault нужно инициализировать.

### Процедура инициализации

Эта команда используется для инициализации Vault и создания начальных ключей разблокировки. Вот что означает каждая часть этой команды:

- `vault`: это исполняемый файл Vault CLI, который вы запускаете.
- `operator`: это подкоманда Vault для выполнения операторских задач, таких как инициализация и настройка Vault.
- `init`: это команда для инициализации Vault.
- `-key-shares=1`: это параметр, который указывает, сколько общих ключей будет создано при инициализации Vault. В данном случае установлено значение 1, что означает, что будет создан только один общий ключ.
- `-key-threshold=1`: это параметр, который указывает, сколько ключей необходимо для разблокировки Vault. В данном случае установлено значение 1, что означает, что для разблокировки Vault потребуется только один ключ.
- `-format=json`: это параметр, который указывает формат вывода результатов инициализации. В данном случае установлен формат JSON.

```sh
kubectl -n vault exec vault-0 -- vault operator init -key-shares=5 -key-threshold=3 -format=json > cluster-keys.json
```

> # Критически важно
>
> Полученный файл нужно сохранить. Без него просто потеряется хранилище Vault. Можно распечатать, создать защищённую заметку, что угодно, но только не потерять.

Получили ключ для unseal:

```sh
cat cluster-keys.json | jq -r ".unseal_keys_b64[]"
```

Ключ сохраняем где-то в сейфе. Потому как он будет необходим при каждом запуске пода Vault.
В нашем случае будем хранить в переменной окружения.

Распечатываем Vault:

```sh
for i in $(cat cluster-keys.json | jq -r '.unseal_keys_b64[:3][]'); do
    kubectl -n vault exec vault-0 -- vault operator unseal $i
    kubectl -n vault exec vault-1 -- vault operator unseal $i
done
```

> ### Стоит упомянуть
>
> Vault необходимо будет распечатывать при каждом перезапуске этим самым unseal key. Поэтому при различных проблемах с перезапуском других pod нужно обращать внимание на статус Vault.
> Так же нужно использовать **как минимум 3 ключа для каждого pod** (автоматизировано циклом, если у вас больше pod, то просто добавьте ещё строку)
> В CI/CD Gitlab эта процедура автоматизирована (см. `gitlab-ci.yml`)

Смотрим, что поды перешли в статус Running.

```sh
kubectl -n vault get pods
```

Кластер Vault собран и готов к работе.

## Хранение Secrets в Vault

Для того чтобы работать в Vault, нам нужно в него логиниться. И для логина нам понадобится Root token.

```sh
cat cluster-keys.json | jq -r ".root_token"
```

- Копируем root token, который получили в выводе.
- Заходим на любой Vault (либо `vault-0`, либо `vault-1`).

```sh
kubectl -n vault exec -it vault-0 -- /bin/sh
```

```sh
vault login
```

Подставляем токен.

### Настраиваем авторизацию Kubernetes и Default lease TTL

```sh
vault auth list
```

Включаем secrets v2:

```sh
vault secrets enable -path=secret kv-v2
```

```sh
vault auth enable kubernetes
```

```sh
vault write auth/kubernetes/config \
kubernetes_host="https://kubernetes.default.svc:443" \
token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
issuer="https://kubernetes.default.svc.cluster.local"
```

> ## Примечание
>
> При перезапуске Vault есть вероятность что придётся повторить этот шаг

> Тут стандартно указываем k8s API, к которому Vault будет обращаться. По сути, тут всё стандартно и менять ничего не нужно.

Проверяем:

```sh
vault read auth/kubernetes/config
```

Командой ниже выставляем Default-lease-ttl, чтобы наш Vault не заполнялся ненужными «арендами».

```sh
vault auth tune -default-lease-ttl=30s kubernetes/
```

## Добавляем Роль, Политику и Секрет

### Для Universe MDM (подойдёт и для Blue/Green стратегии)

#### Роль

```sh
vault write auth/kubernetes/role/mdm \
bound_service_account_names=mdm-sa \
bound_service_account_namespaces=universe-mdm \
policies=universe-mdm-app \
ttl=20m
```

Роль: `mdm`  
Сервисный аккаунт: `mdm-sa`  
Неймспейс: `universe-mdm`  
Название политики: `mdm-app`

> Получается так, что если кто-то из Kubernetes придёт с сервис аккаунтом `mdm-sa` из namespace `universe-mdm`, то будет срабатывать политика `universe-mdm-app`, которая позволяет читать данные из `secret/data/mdm`.

Проверим:

```sh
vault read auth/kubernetes/role/mdm
```

#### Политика

Данная политика выдаёт права доступа для чтения secret для приложения:

```sh
vault policy write universe-mdm-app - <<EOF
path "secret/data/universe_mdm" {
capabilities = ["read"]
}
EOF
```

> В пути секретов нет опечатки. Мы используем secret v2!

Прочитаем политику:

```sh
vault policy read universe-mdm-app
```

> # Важно
>
> Если вы собираетесь редактировать политику, то для этого необходимо её прочитать командой выше. Записать в файл, внести изменения в этот файл и снова записать.

#### Секреты

Положим чувствительные данные:

```sh
vault kv put secret/universe_mdm postgres-address="10.21.2.33:5432" postgres-username="postgres" postgres-password="notpostgres" opensearch-address="10.21.2.33:9200"
```

> Опечаток нет. secret кладём сюда, а брать их будем по пути `secret/data/universe_mdm`

> ### Примечание
>
> Можно посмотреть добавленные секреты в UI. Достаточно ввести команду:

```sh
kubectl port-forward -n vault vault-0 8200:8200
```

> Данная команда разрешит порт на localhost, и вы сможете войти в UI Vault, используя root-token, который мы записали заранее в файл:

```sh
cat cluster-keys.json | jq -r ".root_token"
```

### Для SmartETL

> # Примечание
>
> Для Helm чарта postgresql не будет использоваться хранение секретов в Vault. Так как данный Helm чарт нужен для того, чтобы запустить его один раз для создания баз данных SmartETL и для его последующего удаления. Поэтому чувствительные данные в кластере k8s хранится не будут.

#### Роль

```sh
vault write auth/kubernetes/role/smartetl \
bound_service_account_names=smartetl-sa \
bound_service_account_namespaces=smart-etl \
policies=smartetl-app \
ttl=20m
```

Роль: `smartetl`  
Сервисный аккаунт: `smartetl-sa`  
Неймспейс: `smart-etl`  
Название политики: `smartetl-app`

> Получается так, что если кто-то из Kubernetes придёт с сервис аккаунтом `smart-etl-sa` из namespace `smart-etl`, то будет срабатывать политика `smartetl-app`, которая позволяет читать данные из `secret/data/mdm`.

Проверим:

```sh
vault read auth/kubernetes/role/smartetl
```

#### Политика

Данная политика выдаёт права доступа для чтения secret для приложения:

```sh
vault policy write smartetl-app - <<EOF
path "secret/data/smartetl" {
capabilities = ["read"]
}
EOF
```

> В пути секретов нет опечатки. Мы используем secret v2!

Прочитаем политику:

```sh
vault policy read smartetl-app
```

> # Важно
>
> Если вы собираетесь редактировать политику, то для этого необходимо её прочитать командой выше. Записать в файл, внести изменения в этот файл и снова записать.

#### Секреты

Положим чувствительные данные:

```sh
vault kv put secret/smartetl kc-admin-user="admin" kc-admin-password="admin" kc-db-username="keycloak" kc-postgresql-pass="notpostgres" nifireg-postgresql-pass="notpostgres" keystore-password="th1s1s3up34e5r37" truststore-password="th1s1s3up34e5r37"
```

> Опечаток нет. secret кладём сюда, а брать их будем по пути `secret/data/smartetl`

Немного пояснений:

`kc-admin-user` - задаём пользователя администратора Keycloak (не путать с NiFi)
`kc-admin-password` - задаём пароль для пользователя администратора Keycloak (не путать с NiFi)
`kc-db-username` - имя пользователя для базы данных keycloak для приложения Keycloak
`kc-postgresql-pass` - пароль для доступа к базе данных keycloak для приложения Keycloak
`nifireg-postgresql-pass` - пароль пользователя nifireg для доступа к базе данных nifireg для приложения NiFi-Registry
`keystore-password` - пароль от хранилища ключей NiFi и NiFi-Registry (SSL взаимодействие внутри NiFi и снаружи) (НЕ менее 15 символов)
`truststore-password` - пароль от truststore NiFi и NiFi-Registry (SSL взаимодействие внутри NiFi и снаружи) (НЕ менее 15 символов)

> ### Примечание
>
> Можно посмотреть добавленные секреты в UI. Достаточно ввести команду:

```sh
kubectl port-forward -n vault vault-0 8200:8200
```

> Данная команда разрешит порт на localhost, и вы сможете войти в UI Vault, используя root-token, который мы записали заранее в файл:

```sh
cat cluster-keys.json | jq -r ".root_token"
```

### Для средств мониторинга

У средств мониторинга нет чувствительных данных, которые можно хранить в Vault.
Здесь следует разворачивать Helm чарты из этой [директории](../Helm/monitoring), руководствуясь инструкцией в ней.
Статья в Confluence (дубликат документации): [ссылка на Confluence](https://confluence.unidata-platform.com/pages/viewpage.action?pageId=861995265)

# Монтируем секрет как переменную среды

## Переменные среды для Universe MDM из Vault

Здесь будет показано как настоены Helm чарты для внедрение в переменную среды на примере Helm чарта **MDM Backend**. Предполагается это даст понимание как это устроено, а далее можно делать по аналогии.

#### Откроем для редактирования файл `values.yaml` и обратим внимание на следущий блок

```
vault:
  address: http://vault.vault.svc:8200
  rolename: mdm
  service_account: mdm-sa
  policy_name: universe-mdm-app
  secret_path: secret/data/universe_mdm
```

`address: http://vault.vault.svc:8200` - адрес vault внутри k8s. Состоит из `pod_name.pod_namespace.svc:8200`
`rolename` - имя роли Vault для доступа к секретам (настраивали в Vault выше)
`service_account` - имя сервисного аккаунта для доступа с Vault (задали в Vault выше)
`policy_name` - имя политики Vault, которую настраивали при настройке Vault
`secret_path` - путь до secret в Vault

#### Откроем для просмотра файл `templates/csi-variable.yaml`

Этот манифест определяет, как из Vault извлечь секреты и создать из них Kubernetes Secrets с помощью CSI драйвера. Он указывает, какие секреты должны быть созданы, и настраивает параметры доступа к Vault, такие как адрес сервера Vault и роль, которая используется для получения секретов.

```yaml
secretObjects:
  - data:
      - key: postgres-password
        objectName: postgres-password
    secretName: postgres-password
    type: Opaque
  - data:
      - key: postgres-address
        objectName: postgres-address
    secretName: postgres-address
    type: Opaque
  - data:
      - key: postgres-username
        objectName: postgres-username
    secretName: postgres-username
    type: Opaque
  - data:
      - key: opensearch-address
        objectName: opensearch-address
    secretName: opensearch-address
    type: Opaque
```

`secretObjects`: Определяет, какие секреты будут созданы в Kubernetes на основе данных из Vault.

- `data`: Список ключей и объектов, которые будут извлечены из Vault и сохранены в секретах Kubernetes.
  - `key`: Ключ в созданном секрете Kubernetes.
  - `objectName`: Имя объекта в Vault, соответствующее этому ключу.
- `secretName`: Имя секрета Kubernetes, в который будут помещены данные.
- `type: Opaque`: Тип секрета Kubernetes (в данном случае "Opaque").

```yaml
parameters:
  vaultAddress: "{{ .Values.vault.address }}"
  roleName: "{{ .Values.vault.rolename }}"
  objects: |
    - objectName: "postgres-password"
      secretPath: "{{ .Values.vault.secret_path }}"
      secretKey: "postgres-password"
    - objectName: "postgres-address"
      secretPath: "{{ .Values.vault.secret_path }}"
      secretKey: "postgres-address"
    - objectName: "postgres-username"
      secretPath: "{{ .Values.vault.secret_path }}"
      secretKey: "postgres-username"
    - objectName: "opensearch-address"
      secretPath: "{{ .Values.vault.secret_path }}"
      secretKey: "opensearch-address"
```

`parameters`: Настройки для доступа к Vault.

- `vaultAddress`: Адрес Vault сервера. Используются переменные для шаблонизации (`{{ .Values.vault.address }}`), что позволяет задавать значение через Helm.
- `roleName`: Имя роли в Vault, от которой будут запрашиваться секреты. Также используется шаблонное значение.
- `objects`: Список объектов для извлечения из Vault.
  - `objectName`: Имя объекта в Vault.
  - `secretPath`: Путь в Vault, где хранится объект.
  - `secretKey`: Ключ в объекте Vault, который нужно извлечь.

#### Откроем для просмотра файл `templates/mdm-statefulset.yaml`

```yaml
spec:
  template:
    spec:
      serviceAccountName: "{{ .Values.vault.service_account }}" # Vault
```

- `serviceAccountName`: Это имя учетной записи службы Kubernetes, которая будет использоваться для доступа к секретам в Vault. По этому имени будет создан и использован ServiceAccount.

```yaml
env:
  # << Vault >>>
  - name: POSTGRES_ADDRESS
    valueFrom:
      secretKeyRef:
        name: postgres-address
        key: postgres-address
  - name: POSTGRES_USERNAME
    valueFrom:
      secretKeyRef:
        name: postgres-username
        key: postgres-username
  - name: POSTGRES_PASSWORD
    valueFrom:
      secretKeyRef:
        name: postgres-password
        key: postgres-password
  - name: SEARCH_CLUSTER_ADDRESS
    valueFrom:
      secretKeyRef:
        name: opensearch-address
        key: opensearch-address
  # <<- / Vault -->>
```

- Этот блок определяет переменные окружения для контейнера. Каждая переменная берется из секрета Vault, указанного в `secretKeyRef`. В этом блоке помечены комментариями `<< Vault >>` и `<<- / Vault -->` для обозначения того, что переменные окружения берутся из Vault.

```yaml
volumeMounts:
  - name: secrets-store-inline
    mountPath: "/mnt/secrets-store"
    readOnly: true
    # <<- / Vault -->>
```

- Этот блок определяет местоположение для монтирования тома Kubernetes, который содержит секреты из Vault. Комментарий `# <<- / Vault -->` указывает на то, что том монтируется с использованием данных из Vault.

```yaml
volumes:
  - name: secrets-store-inline
    csi:
      driver: secrets-store.csi.k8s.io
      readOnly: true
      volumeAttributes:
        secretProviderClass: "vault-database"
      # <<- / Vault -->>
```

- Этот блок определяет том Kubernetes, который используется для монтирования секретов из Vault в файловую систему контейнера. Комментарий `# <<- / Vault -->` указывает на то, что том настроен для использования данных из Vault.

Эти блоки позволяют вашему StatefulSet извлекать секреты из Vault и использовать их в контейнерах.

#### Откроем для просмотра файл `templates/service_account.yaml`

Здесь создаётся сервисный аккаунт в Kubernetes, который используется как для Hazelcast Cluster Role, так и для доступа к секретам Vault.

## Общий алгоритм действий при выносе любой переменной в Vault

1. Добавляем значение нового секрета в хранилище Vault (можно как через UI (рекомендуемый способ), так и через shell) [Перейти к разделу Секреты](#секреты)
2. Редактируем по аналогии файл `csi-variable.yaml` в целевом Helm чарте по аналогии.
3. Добавляем в `env` новую переменную в основной манифест (StatefulSet или Deployment)
4. Сохраняем и тестируем.

## Как это устроено в SmartETL?

В Helm чартах SmartETL точно такая же последовательность и аналогия действий, только другие названия. В целом, концептуально, всё абсолютно также.

### Установка Universe MDM

Далее следует классический процесс развёртывания Helm чартов Universe MDM из директории `./application`, о принципе развёртки которого можно прочитать в документации Confluence [здесь](https://confluence.unidata-platform.com/pages/viewpage.action?pageId=856424512) или ReadMe.md текущего Gitlab проекта [здесь](../Helm/MDM/README.md)

Для реализации Blue-Green стратегии:

- [Readme Gitllab](../Helm-Blue-Green-Strategy/MDM/README.md)
- [дубль Readme в Confluence](https://confluence.unidata-platform.com/pages/viewpage.action?pageId=865272187)

### Установка SmartETL

Далее следует классический процесс развёртывания Helm чартов SmartETL из директории `./application`, о принципе развёртки которого можно прочитать в документации Confluence [здесь](https://confluence.unidata-platform.com/pages/viewpage.action?pageId=858882106) или ReadMe.md текущего Gitlab проекта [здесь](../Helm/SmartETL/Readme.md)
