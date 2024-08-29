> Данная документация будет дополняться новыми компонентами

> Сложность: **высокая**

Это означает, что вы уже должны владеть базой Docker и уметь корректировать код, который описан в YAML.
Желательно владеть базовыми командами утилиты `kubectl`
Помимо всего прочего уметь закачивать образы в собтвенный репозиторий контейнеров.

# Требования по утилитам

### Обязательные

Наличие следующих утилилит:

- `kubectl`
- `docker`
- `openssl` (в случае самоподписанного сертификата)
- наличие доступа в собственный репозиторий контейнеров (DockerHub, Gitlab Nexus и др. аналоги)

### k8s

- установленный плагин coreDNS
- установленный и настроенный плагин Ingress
- ноды кластера должны иметь внешнее доменное имя, как индивидуальное, так и одно на всех (CNAME на каждую ноду кластера), например:
  - `k8s-node1.ov.universe-data.ru` `10.21.2.34` -A type
  - `k8s-node2.ov.universe-data.ru` `10.21.2.35` - A type
  - `k8s-node3.ov.universe-data.ru` `10.21.2.36` - A type
  - `cluster-k8s.ov.universe-data.ru` `10.21.2.34` - CNAME type
  - `cluster-k8s.ov.universe-data.ru` `10.21.2.35` - CNAME type
  - `cluster-k8s.ov.universe-data.ru` `10.21.2.36` - CNAME type
    где `10.21.2.34`, `10.21.2.35` и `10.21.2.36` - IP адреса нод кластера Kubernetes
- На каждой ноде кластера должен быть установлен пакет `nfs-common` для корректного взаимодействия с nfs-сервером

### Рекомендации

- Для удобства работы с кластером рекомендуется дополнительно установить утилиту `k9s` на свою машину, с которой планируется установка, в которой достаточно просто наблюдать за процессом развёртывания. [Официальный сайт утилиты](https://k9scli.io/)

# Создание ключей SSL для доменных имён

### Кейс 1: Сертификат выдан центром сертификации

```sh
kubectl create secret tls "example-com-tls" \
    --cert "tls.crt" \
    --key "tls.key" \
    --dry-run=client -o yaml > "secret_file.yaml"
```

Создасться YAML файл `secret_file.yaml` , который необходимо открыть: и скопировать только эти строчки:

```yaml
  tls.crt: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUY1RENDQTh5Z0F3SUJBZ0lVQ0hvWlVrT3JXUEN
  ...
  tls.key: LS0tLS1CRUdJTiBQUklWQVRFIEtFWS0tLS0tCk1JSUpRZ0lCQURBTkJna3Foa2lHOXcwQkFRRUZBQVN
...
```

Необходимо скопировать их без лишних пробелов

И заменить их в файлах:

Для NiFi:

- `/k8s-nifi-cluster/deployment/nifi/secrets.yml`
- `/k8s-nifi-cluster/deployment/nifi/nifi-cluster-secret.yml`
  Для NiFi-Registry:
- `k8s-smartetl/Manifests/nifi-registry/secrets.yml`
- `k8s-smartetl/Manifests/nifi-registry/nifi-registry-cluster-secret.yml`
  Для Keycloak:
- `/Keycloak/secrets.yml`

в секции:

```yaml
data:
  tls.crt: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUY1RENDQTh5Z0F3SUJBZ0lVQ0hvWlVrT3JXUEN...
  tls.key: LS0tLS1CRUdJTiBQUklWQVRFIEtFWS0tLS0tCk1JSUpRZ0lCQURBTkJna3Foa2lHOXcwQkFRRUZBQVN
  ...

```

### Кейс 2: Самоподписанный сертификат

Для использования самоподписанного сертификата и создания из него секрета необходимо воспользоваться скритом, который лежит в корне проекта с манифестами:

- `k8s-smartetl/Manifests/create_custom_cert.sh`

Запуск скрипта:

```
./create_custom_cert.sh <your-domain> 3650
```

Мы создадим таким образом самоподписанные сертификаты и сразу секреты к ним, который обязательно надо будет заменить в манифесте приложения. Сроком на 10 лет. Если сертификат нужен на более или менее продолжительный промежуток времени, то необходимо заменить этот параметр на меньшее или большее время.

Создасться YAML файл `<your_domain>-tls.yaml` , который необходимо открыть, после
чего из него скопировать только эти строчки:

```yaml
  tls.crt: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUY1RENDQTh5Z0F3SUJBZ0lVQ0hvWlVrT3JXUEN
  ...
  tls.key: LS0tLS1CRUdJTiBQUklWQVRFIEtFWS0tLS0tCk1JSUpRZ0lCQURBTkJna3Foa2lHOXcwQkFRRUZBQVN
...
```

И заменить их в файлах

Для NiFi:

- `/k8s-nifi-cluster/deployment/nifi/secrets.yml`
- `/k8s-nifi-cluster/deployment/nifi/nifi-cluster-secret.yml`
  Для NiFi-Registry:
- `k8s-smartetl/Manifests/nifi-registry/secrets.yml`
- `k8s-smartetl/Manifests/nifi-registry/nifi-registry-cluster-secret.yml`
  Для Keycloak:
- `/Keycloak/secrets.yml`

в секции подставивить свои значения:

```yaml
data:
  tls.crt: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUY1RENDQTh5Z0F3SUJBZ0lVQ0hvWlVrT3JXUEN...
  tls.key: LS0tLS1CRUdJTiBQUklWQVRFIEtFWS0tLS0tCk1JSUpRZ0lCQURBTkJna3Foa2lHOXcwQkFRRUZBQVN
  ...
```

# Создаём секрет для доступа к хранилищу образов контейнеров (опционально)

В случае, если у нас имеется собственное хранилище образов контейнеров, то необходмо в манифестах создать secret.

Все подробности по созданию и внедреню secrets находятся в данной [статье](https://confluence.unidata-platform.com/pages/viewpage.action?pageId=820215821)

1. Авторизуемся на целевом репозиторий контенеров. Пример команды:

```sh
docker login docker.universe-data.ru -u <your_username> -p <your_password>
```

, где `docker.universe-data.ru` - адрес вашего хранилища репозриториев.

2. После успешно пройденной авторизации файл для аутентификации на UNIX системах будет располагаться в `~/.docker/config.json`. Перейдите в эту директорию и выполните команду для создания secret:

```sh
kubectl create secret generic universe-nexus \kube
--from-file=./config.json \
--dry-run=client -o yaml > universe-nexus.yaml
```

где `universe-nexus` замените на название своего `secret`.

3. Экспортируем получившийся secret в k8s:

```sh
kubectl apply -f ./universe-nexus.yaml -n universe
```

, где `-n universe` - имя вашего namespace.

3.1. Проверяем:

```sh
kubectl get secrets -n universe universe-nexus -o yaml
```

## Внедрение секретов в манифесты

Внедрение secrets требуется во всех манифестах, в которых требуется использование образов из закрытых репозиториев. Смените адрес образа на нужный вам в файлах:

- `k8s-nifi-cluster/deployment/nifi/nifi.yml`
- `k8s-nifi-cluster/deployment/zookeeper/zookeeper.yml`
- `k8s-smartetl/Manifests/Keycloak/deployment.yaml`
- `k8s-smartetl/Manifests/nifi-registry/nifi-registry.yml`
- `k8s-smartetl/Manifests/postgresql/deployment.yaml`

Пример строки:

```yaml
image: postgres:14-alpine
```

После чего добавьте в конце каждого манифеста ссылку на secret, который будет применяться для авторизации в репозитории:

```yaml
imagePullSecrets:
  - name: universe-nexus
```

, где `universe-nexus` - имя вашего secret

Сделать это нужно на том же уровне отступа, что и `containers`.
Пример манифеста для понимания:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  labels:
    app: frontend

spec:
  # Deployment History
  revisionHistoryLimit: 15
  # Count of replicas
  replicas: 3
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: app
                    operator: In
                    values:
                      - frontend
      containers:
        - name: frontend
          image: gitlab.praktikum-services.ru:5050/std-020-022/sausage-store/sausage-frontend:c194839203ca44d1e10d8196c35c1137a33b7672
          imagePullPolicy: IfNotPresent
          ports:
            - name: frontend
              containerPort: 80
          volumeMounts:
            - name: docker-socket
              mountPath: /tmp/docker.sock
              readOnly: true
            - name: nginx-conf
              mountPath: /etc/nginx/nginx.conf
              subPath: nginx.conf
              readOnly: true
      imagePullSecrets:
        - name: universe-nexus
      volumes:
        - name: docker-socket
          hostPath:
            path: /var/run/docker.sock
        - name: nginx-conf
          configMap:
            name: nginx-conf
            items:
              - key: nginx.conf
                path: nginx.conf
```

# Базы данных

> ## Важно
>
> У вас уже должен быть запущен и настроен PostgreSQL сервер. Данный манифест только запускает скрипт, который создаёт базы данных и пользователей.

В первую очередь необходимо запустить манифест, который создаст базы данных. И после того как базы будут созданны необходимо удалить этот манифест.

Файлы с манифестами находятся в каталоге: `postgresql`

## Правка ConfigMap

Открываем файл `posgresql/configmap.yaml` для редактирования и задаём параметры в секции на свои:

```YAML
...
data:
  POSTGRES_HOSTNAME: 10.21.2.33
  POSTGRES_INNER_PORT: "5432"
  POSTGRES_OUTER_PORT: "5432"
  POSTGRES_PASSWORD: notpostgres
  POSTGRES_USER: postgres
...
```

Возможно вы захотите сменить пароли для пользователей, которых создаёт скрипт, это будет видно в манифесте ниже. В случае, если вы смените пароли, то просьба сменить их во всех `ConfigMap` манифестов, которые будут встречаться в дальнейшем.

## Применение манифеста

Для применения манифеста воспользуемся командой:

```sh
kubectl apply -f ./postgresql
```

### После применения манифеста

После применения манифеста необходимо посмотреть логи, а возможно `describe` контейнера, чтобы убедиться, что скрипт отработал успешно. (Это достаточно удобно сделать через утилиту `k9s`) После чего зайти на сервер PostgreSQL и убедиться, что базы данных и пользователи были созданы. Только после этого перейти к удалению манифеста.

## Удаление манифеста

Для удаления манифеста воспользуемся командой:

```sh
kubectl delete -f ./postgresql
```

# Установка и настройка Keycloak

Стоит понимать, что Keycloak нельзя масштабировать "на ходу" (получится исправить в helm чарте) ввиду следующих параметров, которые должны соответствовать количествую реплик в кластере:

```
  CACHE_OWNERS_COUNT: "1"
  CACHE_OWNERS_AUTH_SESSIONS_COUNT: "1"
```

Поэтому лучше заранее определиться с количеством нод в кластере.

## Редактирование конфигурационных файлов

1. Открываем следующий файл для редактирования `Keycloak/configmap.yaml`

- Меняем все вхождения доменных имён на свои;
- URL, IP и порт (при необходимости) для подключения к собственной базе данных PostgreSQL
- Выставляем значение в параметрах `CACHE_OWNERS_COUNT: "1"` и `CACHE_OWNERS_AUTH_SESSIONS_COUNT: "1"` на количество реплик кластера.

2. Открываем для редактирования файл `Keycloak/deployment.yaml`

- Меняем значение `replicas` на желаемое количество реплик (обязательно должно соответствовать `CACHE_OWNERS_COUNT: "1"` и `CACHE_OWNERS_AUTH_SESSIONS_COUNT: "1"`):

```yaml
spec:
  replicas: 1
```

3. Открываем файл для редактирования `Keycloak/ingress.yaml

- меняем все вхождения доменных имён на свои (их всего 2)

4. Открываем файл для редактирования `Keycloak/ingress.yaml

- и меняем все вхождения доменных имён на свои (**Не трогать значение поля secret Name** )

Создадим пространство имён в кластере k8s (если ещё не создали):

```sh
kubectl create namespace universe
```

Применим манифесты:

```sh
kubectl apply -f ./Keycloak -n universe
```

Проверяем доступность keycloak в браузере. Если всё сделано правильно, то keycloak будет доступен по адресу:

```
https://cluster.lan/keycloak/auth/
```

,где вместо `cluster.lan` следует подставить ваше доменное имя

### Заранее добавим клиента SAML для NiFi

Откройте конфигурационный файл клиента Keycloak `k8s-smartetl/Manifests/conf_keycloak/org_apache_nifi_saml_all.json` и с помощью поиска и замены замените все вхождения доменных имён на своё доменное имя.

Переходим в `https://cluster.lan/keycloak/auth/` и вводим пароль от консоли администратора, который вы указали в ConfigMap Keycloak

`Clients` -> `Import client` -> `Browse...`

- и импортируем файл.
- Сохраняем

После чего сохраняем и выходим.

### Заранее добавим клиента OIDC для NiFi-Registry

Откройте конфигурационный файл клиента Keycloak `k8s-smartetl/Manifests/conf_keycloak/org_apache_nifi-reg_oidc_all.json` и с помощью поиска и замены замените все вхождения доменных имён на своё доменное имя.

Переходим в `https://cluster.lan/keycloak/auth/` и вводим пароль от консоли администратора, который вы указали в ConfigMap Keycloak

`Clients` -> `Import client` -> `Browse...`

- и импортируем файл.
- Сохраняем

После чего сохраняем и выходим.

# Установка и настройка NiFi

ВАЖНО! Не меняйте политику развёртывания StatefulSet. Особенность NiFi в том, что ноды кластера должны запускаться поочерёдно, что они и делают.

## Подготовка

Для того чтобы развернуть манифесты NiFi необходимо подготовится:

- Запустить zookeeper, для координации элементов кластера NiFi
- настроить NFS хранилище таким образом, чтобы в него имел доступ кластер k8s.

### Настройка Zookeeper

По умолчанию, ограничение кластера - 3 ноды. Как его увеличить будет описано далее.

Все манифесты zookeeper находятся в каталоге `/k8s-nifi-cluster/deployment/zookeeper/`

#### Увеличение/уменьшение количества нод кластера

Стоит понимать, что количество нод по аналогии с базой `etcd` рекеомедуется быть **нечётным**, то есть следующий шаг увеличения 5 нод, а на уменьшение 1.

Для увеличения или уменьшения количества нод кластера будем редактировать следующий набор файлов:

- `zookeeper.yml`
- `hpa.yml`

В `zookeeper.yml` изменим значение следующего параметра (опционально):

```YAML
- name: ZOO_SERVERS
  value: "server.1=zookeeper-0.zookeeper.$(POD_NAMESPACE).svc.cluster.local:2888:3888;2181 server.2=zookeeper-1.zookeeper.$(POD_NAMESPACE).svc.cluster.local:2888:3888;2181 server.3=zookeeper-2.zookeeper.$(POD_NAMESPACE).svc.cluster.local:2888:3888;2181"
```

, где через пробел добавим доменное имя ещё одного элемента кластера (либо удалим сушествующий)

Формат имени должен быть следующим:

`server.3=zookeeper-2.zookeeper.$(POD_NAMESPACE).svc.cluster.local:2888:3888;2181`

где:

`server.3` - порядковый номер сервера zookeeper;
`zookeeper-2` - доменное имя, которое определяет порядковый номер pod в StatefulSet (начинается с 0).
Все остальные значения оставляем по умолчанию.

В файле `hpa.yml` меняем только секцию:

```
  minReplicas: 3
  maxReplicas: 3
```

где `minReplicas` и `maxReplicas` должны иметь одинаковые значения. Например 5 или 1.

#### Применим манифест

Применяем манифест следующей командой:

```sh
kubectl apply -k k8s-nifi-cluster/deployment/zookeeper -n universe
```

### Настройка NFS

Базовая настройка NFS описана достаточно хорошо [здесь](https://www.digitalocean.com/community/tutorials/how-to-set-up-an-nfs-mount-on-ubuntu-20-04-ru)

Листинг `/etc/exports` прописал такой, что он гарантировано даёт доступы для Kubernetes Однако для более детальной настройки безопасноти необходимо обратиться к ==документации NFS.==

```sh
# /etc/exports: the access control list for filesystems which may be exported
#  to NFS clients.  See exports(5).
#
# Example for NFSv2 and NFSv3:
# /srv/homes       hostname1(rw,sync,no_subtree_check) hostname2(ro,sync,no_subtree_check)
#
# Example for NFSv4:
# /srv/nfs4        gss/krb5i(rw,sync,fsid=0,crossmnt,no_subtree_check)
# /srv/nfs4/homes  gss/krb5i(rw,sync,no_subtree_check)
#
#/data/nfs       10.21.0.0/16(rw,sync,root_squash,nohide,no_subtree_check,all_squash)
#/data/nfs       0.0.0.0/0(rw,sync,root_squash,nohide,no_subtree_check,all_squash)
#/var/nfs/nifi    10.0.0.0/8(rw,all_squash,no_subtree_check,nohide)
/var/nfs/nifi    10.0.0.0/8(rw,all_squash,no_subtree_check,nohide)
```

В данном случае имеется общий доступ на каталог на сервере NFS:

- `/var/nfs/nifi`
  Да, для теста выдан доступ для целой сети `10.0.0.0/8` так как сервер k8s и ПК для разработки находятся в разных подсетях. Исключительно для удобства.

Права доступа для каталогов рекурсивно необходимо выдать так:

```sh
chown -R nobody:nogroup /var/nfs/nifi
```

Перезагружаем сервер nfs:

```sh
systemctl restart nfs-server
```

Монтируем каталог с NFS на вашу локальную машину (либо копируем каталог по сети, о чем будет рассказано далее)

### Настройка PersistentVolume и PersistentVolumeClaim

> Для полного понимания монтирования PV и PVC матчасть находится: [здесь](https://confluence.unidata-platform.com/pages/viewpage.action?pageId=817922085) и [здесь](https://confluence.unidata-platform.com/pages/viewpage.action?pageId=819494922)

- Переходим в каталог `k8s-nifi-cluster/volumes(not_to_delete)`
- Открываем файл `pv.yaml` для редактирования, в котором меняем только две строчки внизу:

```
  nfs:
    path: /var/nfs/nifi/
    server: 10.21.2.33
```

где `/var/nfs/nifi/` - это путь до родительского каталога в вашем NFS хранилище. То есть не надо указывать путь до папок, которые мы создали внутри каталога.
и `10.21.2.33` - непосредственно прописываем свой IP адрес NFS хранилища;

#### Применяем volumes

Создадим пространство имён в кластере k8s (если ещё не создали):

```sh
kubectl create namespace universe
```

Примонтируем наше хранилище данных, применив манифест

```sh
kubectl apply -f ./volumes(not_to_delete) -n universe
```

`-n universe` - ваше пространство имён

> Для понимания пространств имён можно почитать [статью](https://confluence.unidata-platform.com/pages/viewpage.action?pageId=820871185)

##### Проверяем

```
kubectl get pv
```

```
NAME               CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      CLAIM                        STORAGECLASS   VOLUMEATTRIBUTESCLASS   REASON   AGE
nfs-pv-nifi-data   3Gi        RWO,ROX        Recycle          Bound       universe/nfs-pvc-nifi-data   nfs            <unset>                          47m
```

```
kubectl get pvc -n universe
```

```
NAME                STATUS   VOLUME             CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
nfs-pvc-nifi-data   Bound    nfs-pv-nifi-data   3Gi        RWO,ROX        nfs            <unset>                 49m
```

Статус должен быть либо **Bound** либо **Availible**

### Добавляем наши библиотеки и расширения в NFS хранилище

На NFS сервере предполагается, что у вас создан каталог `/var/nfs/nifi` и возможно уже успешно примонтирован (рекомендую примонтировать, чтобы убедиться в том, что с всё в порядке и вы можете работать с nfs хранилищем)

Копируем содержимое каталога `/k8s-smartetl/Manifests/k8s-nifi-cluster/VOLUME_DATA` в наше nfs хранилище. В итоге должна получится вот такая структура в корне NFS хранилища:

```
├── conf
│   ├── authorizers.xml
│   ├── logback.xml
│   ├── login-identity-providers.xml
│   └── state-management.xml
├── custom-libs
│   └── postgresql-42.2.2.jar
└── extensions
    └── nifi-smartetl-nar-1.0.nar
```

## Настраиваем Ingress

Для настройки Ingress `/k8s-nifi-cluster/deployment/nifi/ingress.yaml`
И меняем все вхождения доменных имён, например `cluster-k8s.ov.universe-data.ru` (их всего 2)
на своё доменное имя, которые соответствуют сертификату, который мы создавали вначале **Это важно** (**Не трогать значение поля secret Name** )

## Правим ConfigMap

Обязательно меняем вхождения доменных имён на свои:

Расположение файла: `/k8s-nifi-cluster/deployment/nifi/configmap.yml`

- `NIFI_WEB_PROXY_HOST: "cluster.lan"`
- `NIFI_SECURITY_USER_SAML_IDP_METADATA_URL: "https://cluster.lan/keycloak/auth/realms/master/protocol/saml/descriptor"`
- `DOMAIN: "cluster.lan"`
- `K8S_NODES` - перечислить доменные имена нод кластера через запятую

Остальные параметры следует менять на ваше усмотрение, такие как пароли, например.

## Правим hpa.yml (опционально)

Расположение файла: `/k8s-nifi-cluster/deployment/nifi/hpa.yml`

В данном файле необходимо определить количество нод кластера в секции:

```yaml
minReplicas: 3
maxReplicas: 8
```

> Пока ограничение установлено на 20 реплик. При необходимости увеличить это количество реплик, следует расширить список доменных имён в файле `/k8s-nifi-cluster/deployment/nifi/ssl-configmap.yml`

## Применяем манифест

```sh
kubectl apply -k k8s-nifi-cluster/deployment/nifi -n universe
```

# Донастройка Keycloak

## Импорт keystore

После того как NiFI развёрнётся на NFS хранилище будет создан `keystore.jks` в каталоге `keytool/all` и его необходимо импортировать в Keycloak:

- Переходим в консоль администратора Keycloak
- `Clients`
- Вкладка `Keys`
- `Import Key`
- Key alias вводим: `nifi-key`
- Ввводим пароль из ConfigMap NiFi для Keystore.

# Установка и настройка NiFi-Registry

> **На данный момент NiFi-Registry может работать только в singe-mode. То есть запуск нескольких нод недопустим.**

Все манифесты необходмые для установки находятся по пути: `k8s-smartetl/Manifests/nifi-registry/`

Для того, чтобы установить NiFi-Registry необходимо:

- Пересобрать образ контейнера под ваше доменное имя

## Патчим Container Image под ваше доменное имя

По своей сути это нужно для того, чтобы добавить в базовый образ наш доменный сертификат ввиду того, что NiFi-Registry в отличие от NiFi не имеет опции стратегии получения доменного сертификата из keystore.

Для того, чтобы собрать образ необходимо.

1. Перети в директорию `k8s-smartetl/Manifests/nifi-registry/docker/` в которой уже находится Dockerfile с готовыми инструкциями для пересборки.

   2.1. На шаге **Создание ключей SSL для доменных имён** мы уже с помощью скрипта создали самоподписанный сертификат, который будет иметь имя `<ваш_домен>.сrt`.

   2.2. Положите его рядом с Dockerfile. После чего переименуйте название файла `<ваш_домен>.сrt` в `keycloak.crt`.

   2.3. После чего запустите сборку образа командой, в которой замените параметры названия образа под ваше хранилище (документация [тут](https://docs.docker.com/reference/cli/docker/image/push/)):

```sh
docker build -t epostnikof/nifi-registry-domain:1.24.0 .
```

> _Команда даём навание образа, чтобы потом загрузить на DockerHub_. В случае если у вас имеется другое хранилище (Nexus или Gitlab), то просьба ознакомиться с документацией по загрузки образов в него.

2.4. После сборки необходимо загрузить образ в ваш репозиторий образов контейнеров.
Пример команды:

```sh
docker push epostnikof/nifi-registry-domain:1.24.0
```

### Настройка NFS

Базовая настройка NFS описана достаточно хорошо [здесь](https://www.digitalocean.com/community/tutorials/how-to-set-up-an-nfs-mount-on-ubuntu-20-04-ru)

Листинг `/etc/exports` прописал такой, что он гарантировано даёт доступы для Kubernetes Однако для более детальной настройки безопасноти необходимо обратиться к ==документации NFS.==

```sh
# /etc/exports: the access control list for filesystems which may be exported
#  to NFS clients.  See exports(5).
#
# Example for NFSv2 and NFSv3:
# /srv/homes       hostname1(rw,sync,no_subtree_check) hostname2(ro,sync,no_subtree_check)
#
# Example for NFSv4:
# /srv/nfs4        gss/krb5i(rw,sync,fsid=0,crossmnt,no_subtree_check)
# /srv/nfs4/homes  gss/krb5i(rw,sync,no_subtree_check)
#
#/data/nfs       10.21.0.0/16(rw,sync,root_squash,nohide,no_subtree_check,all_squash)
#/data/nfs       0.0.0.0/0(rw,sync,root_squash,nohide,no_subtree_check,all_squash)
#/var/nfs/nifi    10.0.0.0/8(rw,all_squash,no_subtree_check,nohide)
/var/nfs/nifi    10.0.0.0/8(rw,all_squash,no_subtree_check,nohide)
/var/nfs/nifireg    10.0.0.0/8(rw,all_squash,no_subtree_check,nohide)
```

В данном случае имеет общий доступ два каталога на сервере NFS:

- `/var/nfs/nifi`
- `/var/nfs/nifireg`

Да, для теста выдан доступ для целой сети `10.0.0.0/8` так как сервер k8s и ПК для разработки находятся в разных подсетях. Исключительно для удобства.

Права доступа для каталогов рекурсивно необходимо выдать так:

```sh
chown -R nobody:nogroup /var/nfs/nifireg
```

Монтируем каталог с NFS на вашу локальную машину (либо копируем каталог по сети, о чем будет рассказано далее)

### Настройка PersistentVolume и PersistentVolumeClaim

> Для полного понимания монтирования PV и PVC матчасть находится: [здесь](https://confluence.unidata-platform.com/pages/viewpage.action?pageId=817922085) и [здесь](https://confluence.unidata-platform.com/pages/viewpage.action?pageId=819494922)

- Переходим в каталог `k8s-smartetl/Manifests/nifi-registry/volumes(not_to_delete)/`
- Открываем файл `pv-nifireg.yaml` для редактирования, в котором меняем только две строчки внизу:

```
  nfs:
    path: /var/nfs/nifireg/
    server: 10.21.2.33
```

где `/var/nfs/nifireg/` - это путь до родительского каталога в вашем NFS хранилище. То есть не надо указывать путь до каталогов, которые мы создали внутри каталога.
и `10.21.2.33` - непосредственно прописываем свой IP адрес NFS хранилища;

#### Применяем volumes

Создадим пространство имён в кластере k8s (если ещё не создали):

```sh
kubectl create namespace universe
```

Примонтируем наше хранилище данных, применив манифест

```sh
kubectl apply -f ./volumes(not_to_delete) -n universe
```

`-n universe` - ваше пространство имён

> Для понимания пространств имён можно почитать [статью](https://confluence.unidata-platform.com/pages/viewpage.action?pageId=820871185)

##### Проверяем

```
kubectl get pv nfs-pv-nifireg-data

NAME                  CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                           STORAGECLASS   VOLUMEATTRIBUTESCLASS   REASON   AGE
nfs-pv-nifireg-data   30Gi       ROX,RWX        Recycle          Bound    universe/nfs-pvc-nifireg-data   nfs            <unset>                          8d
```

```
 kubectl get pvc -n universe nfs-pvc-nifireg-data

NAME                   STATUS   VOLUME                CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
nfs-pvc-nifireg-data   Bound    nfs-pv-nifireg-data   30Gi       ROX,RWX        nfs            <unset>                 8d
```

Статус должен быть либо **Bound** либо **Availible**

### Добавляем наши библиотеки и расширения в NFS хранилище

На NFS сервере предполагается, что у вас создан каталог `/var/nfs/nifireg` и возможно уже успешно примонтирован (рекомендую примонтировать, чтобы убедиться в том, что с всё в порядке и вы можете работать с nfs хранилищем)

Копируем содержимое каталога `k8s-smartetl/Manifests/nifi-registry/VOLUME_DATA/` в наше NFS хранилище. В итоге должна получится вот такая структура в корне NFS хранилища:

````
├── conf
│   ├── authorizations.xml
│   ├── authorizers.xml
│   ├── identity-providers.xml
│   ├── providers.xml
│   ├── registry-aliases.xml
│   └── users.xml
├── custom-libs
│   └── postgresql-42.2.2.jar
├── extensions
├── flow
└── flow_storage
   ```

## Настраиваем Ingress

Для настройки Ingress `k8s-smartetl/Manifests/nifi-registry/secrets.yml`
И меняем все вхождения доменных имён, например `cluster-k8s.ov.universe-data.ru` (их всего 2)
на своё доменное имя, которые соответствуют сертификату, который мы создавали вначале **Это важно** (**Не трогать значение поля secret Name** )

### Правим ConfigMap

Обязательно меняем вхождения доменных имён на свои:

Расположение файла: `/k8s-nifi-cluster/deployment/nifi/configmap.yml`

-  `NIFI_REGISTRY_SECURITY_USER_OIDC_DISCOVERY_URL: "https://cluster-k8s.ov.universe-data.ru/keycloak/auth/realms/master/.well-known/openid-configuration"` - обратить внимание на realms `master` возможно у вас будет другой.
- `DOMAIN: "cluster-k8s.ov.universe-data.ru"`
- `K8S_NODES` - перечислить доменные имена нод кластера через запятую

Указать учётные данные вашей базы данных PostgreSQL:

``` yaml
  ##DATABASE##
  NIFI_REGISTRY_DB_URL: "jdbc:postgresql://10.21.2.33:5432/nifireg"
  NIFI_REGISTRY_DB_USER: "nifireg"
  NIFI_REGISTRY_DB_PASS: "nifireg"
  NIFI_REGISTRY_DB_CLASS: "org.postgresql.Driver"
````

Остальные параметры следует менять на ваше усмотрение, такие как пароли, например.

## Применяем манифест

```sh
kubectl apply -k k8s-smartetl/Manifests/nifi-registry -n universe
```

## Подключение NiFi-Registry к NiFi после установки

После того как приложение NiFi-Registry и NiFi будет запущено необходимо их связать друг с другом.
Сервисы будут доступны по адресам:

**NiFi-Registry**

```
<your_domain>/nifi-registry/
```

**NiFi**

```
<your-domain>/nifi/
```

- Переходим в **NiFi-Registry**
- `Settings` -> `Buckets` -> `New Bucket`
- Задаем любое удобное имя для bucket -> Create
- `Settings` -> `Users`
  - Создаём если не существуют следующий набор пользователей:
  - `CN=localhost, OU=NIFI`
  - `admin
  - Проверяем права. Важно понимать, что пользователи должны иметь права администратора. То есть полные права к системе:

```
Special Privileges 

Can manage buckets

Read Write Delete

Can manage users

Read Write Delete

Can manage policies

Read Write Delete

Can proxy user requests

Read Write Delete
```

- Переходим в **NiFi**
- `Controller Setttings`
- Вкладка `Registry Clients`
- Создаём нового клиента
- После чего открываем для редактирования созданного клиента (иконка "карандаш" в справа)
- Вкладка `Properties`
- Заполняем URL следующим образом: `https://nifi-registry:18443`
- После чего закрываем настройки
- Переходим на Flow
- Если у вас уже есть созданный Flow, то на нём нажимаем ПКМ -> `Start Version Control`
- После чего выбираем Registry Client и Bucket из выпадающего списка

Готово. Взаимодействие NiFi и NiFi-Registry настроено.
Для проверки можно внести любое незначительное изменение в Flow NiFi и попробовать сделать коммит. После чего перейти в NiFi-Registry и убедиться, что изменения поступили.
