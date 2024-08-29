---
aliases:
tags:
  - DevOps
  - Kubernetes
  - note
  - k8s
  - Universe
  - SmartETL
  - Helm
source:
---

# Требования по утилитам

### Обязательные

Наличие следующих утилилит:

- `kubectl`
- `helm` - версия 3
- `docker`
- `openssl` (в случае самоподписанного сертификата)
- наличие доступа в собственный репозиторий контейнеров (DockerHub, Gitlab Nexus и др. аналоги)
- Установленный и настроенный сервер `PostgreSQL` 12, 13 или 14 версии;

### k8s

- установленный плагин coreDNS
- установленный и настроенный плагин Ingress
- ноды кластера должны иметь внешнее доменное имя, как индивидуальное, так и одно на всех (CNAME на каждую ноду кластера), например:
  - `k8s-node1.ov.universe-data.ru` `10.21.2.34` -A type
  - `k8s-node2.ov.universe-data.ru` `10.21.2.35` - A type
  - `k8s-node3.ov.universe-data.ru` `10.21.2.36` - A type
  - `your_domain` `10.21.2.34` - CNAME type
  - `your_domain` `10.21.2.35` - CNAME type
  - `your_domain` `10.21.2.36` - CNAME type
    где `10.21.2.34`, `10.21.2.35` и `10.21.2.36` - IP адреса нод кластера Kubernetes
- На каждой ноде кластера должен быть установлен пакет `nfs-common` для корректного взаимодействия с nfs-сервером

### Рекомендации

- Для удобства работы с кластером рекомендуется дополнительно установить утилиту `k9s` на свою машину, с которой планируется установка, в которой достаточно просто наблюдать за процессом развёртывания. [Официальный сайт утилиты](https://k9scli.io/)

# Подготовка к установке

## Настройка PostgreSQL

Запустите сервер PostgreSQL любым удобным для вас методом на отдельном сервере, опираясь на официальное руководством по [ссылке](https://doc.ru.universe-data.ru/6.10.0-EE/content/guides/install/ubuntu_online.html#postgresql)с пропуском 9 шага (Создание базы данных).

## Создание namespace в k8s

Для создания namespace воспользуемся следующей командой:

```sh
kubectl create namespace smart-etl
```

Проверка:

```sh
kubectl get namespaces
```

## Создание secret для доступа в репозиторий контейнеров

> ### Примечание
>
> Этот шаг принципиально важен в случах:
>
> - если вы планируете запустить компонент NiFi-Registry.
> - если образы контейнеров будут браться из вашего репозитория

Прежде всего, для того, чтобы Kubernetes мог скачать образы контейнеров необходимо указать ему данные для авторизации в формате `base64`

Для получения `<base64-encoded-json>`, необходимо выполнить команду:

```
echo -n '{"auths": {"docker.test.ru": {"username": "docker", "password": "hUio7655Gbet@OOp02m=="}}}' | base64
```

,где
**Адрес Docker registry**: `docker.test.ru`
**Пользователь**: `docker`
**Пароль**: `hUio7655Gbet@OOp02m==`

Необходимо заменить на свои.

> **Важно**
> Вывод может содержать знаки переноса строки:

```
eyJhdXRocyI6IHsiZG9ja2VyLnRlc3QucnUiOiB7InVzZXJuYW1lIjogImRvY2tlciIsICJwYXNz
d29yZCI6ICJoVWlvNzY1NUdiZXRAT09wMDJtPT0ifX19
```

> Необходимо убрать символ переноса строки в любом текстовом редакторе, чтобы уместить вывод в одну строку:

```
eyJhdXRocyI6IHsiZG9ja2VyLnRlc3QucnUiOiB7InVzZXJuYW1lIjogImRvY2tlciIsICJwYXNzd29yZCI6ICJoVWlvNzY1NUdiZXRAT09wMDJtPT0ifX19
```

Таким образом мы получим значение `base64` для доступа к Docker registry.

Сохраните это значение в отдельный файл, чтобы позже скопировать его.

За дополнительной информацией обратитесь к официальной [документации](https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/)

## Создание ключей SSL для доменных имён (SSL)

### Кейс 1: Сертификат выдан центром сертификации

```sh
kubectl create secret tls "example-com-tls" \
    --cert "tls.crt" \
    --key "tls.key" \
    --dry-run=client -o yaml > "secret_file.yaml"
```

Создасться YAML файл `secret_file.yaml`, в котором нам в дальнейшем пригодятся значения строк с ключами `tls.crt` и `tls.key`:

```yaml
  tls.crt: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUY1RENDQTh5Z0F3SUJBZ0lVQ0hvWlVrT3JXUEN
  ...
  tls.key: LS0tLS1CRUdJTiBQUklWQVRFIEtFWS0tLS0tCk1JSUpRZ0lCQURBTkJna3Foa2lHOXcwQkFRRUZBQVN
...
```

### Кейс 2: Самоподписанный сертификат

Для использования самоподписанного сертификата и создания из него секрета необходимо воспользоваться скриптом. Скопируйте листинг данного скрипта и создайте файл `create_custom_cert.sh` со следующим содержанием:

```sh
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

```

Запуск скрипта:

```
chmod +x ./create_custom_cert.sh && ./create_custom_cert.sh <your-domain> 3650
```

> #### Примечание
>
> Замените `<your-domain>` на ваше действительное доменное имя.

Мы создадим таким образом самоподписанные сертификаты и сразу секреты к ним cроком на 10 лет. Если сертификат нужен на более или менее продолжительный промежуток времени, то необходимо заменить этот параметр на меньшее или большее время.

Создасться YAML файл `<your_domain>-tls.yaml`, в котором нам в дальнейшем пригодятся значения строк с ключами `tls.crt` и `tls.key`:

```yaml
  tls.crt: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUY1RENDQTh5Z0F3SUJBZ0lVQ0hvWlVrT3JXUEN
  ...
  tls.key: LS0tLS1CRUdJTiBQUklWQVRFIEtFWS0tLS0tCk1JSUpRZ0lCQURBTkJna3Foa2lHOXcwQkFRRUZBQVN
...
```

# Создание необходимых баз данных для компонентов приложения

Открываем файл `posgresql/value.yaml` для редактирования и задаём параметры в секции на свои:

- `dockerconfigjson: []` - удалите символы `[]` и замените их на значение, которые вы получили в разделе [Создание secret для доступа в репозиторий контейнеров](#создание-secret-для-доступа-в-репозиторий-контейнеров).

> Заполняется опционально, только в том, случае, если используется приватный репозиторий. В ином случае пропустите этот шаг.

Пример заполнения:

```yaml
dockerconfigjson: eyJhdXRocyI6IHsiZG9ja2VyLnRlc3QucnUiOiB7InVzZXJuYW1lIjogImRvY2tlciIsICJwYXNzd29yZCI6ICJoVWlvNzY1NUdiZXRAT09wMDJtPT0ifX19
```

Пример заполнения остальных параметров:

```YAML
  ##Задаём параметры для подключения к серверу PostgreSQL##
  postgres_hostname: "10.21.2.33"
  postgres_inner_port: "5433"
  postgres_password: "notpostgres"
  postgres_user: postgres
  ##Установим пароль для пользователя keycloak, чтобы он мог подключаться к базе данных keycloak
  keycloak_user_password: "notpostgres"
  ##Установим пароль для пользователя nifireg, чтобы он мог подключаться к базе данных nifireg
  nifireg_user_password: "notpostgres"

```

## Деплой в Kubernetes. Применение Helm чарта

Для применения Helm чарта воспользуемся командой:

```sh
helm install postgresql-deploy ./postgresql -n smart-etl
```

### После применения helm чарта

После применения helm чарта необходимо посмотреть логи, а возможно `describe` контейнера, чтобы убедиться, что скрипт отработал успешно. (Это достаточно удобно сделать через утилиту `k9s`) После чего зайти на сервер PostgreSQL и убедиться, что базы данных и пользователи были созданы. Только после этого перейти к удалению helm чарта.

```sh
kubectl describe deployments -n smart-etl postgresql-deployment
```

```sh
kubectl logs -f -n smart-etl postgresql-deployment-7ffbd5474b-j6d5m
```

> Название `Deployment` может быть другим, пожалуйста, используйте автодополнение или уточните название с помощью команды: `kubectl get all -n smart-etl`

## Удаление helm чарта

Для удаления helm чарта воспользуемся командой:

```sh
helm uninstall -n smart-etl postgresql-deploy
```

# Установка компонента Keycloak

Helm чарт для Keycloak находится в каталоге `keycloak`

## Заполняем обязательные параметры

Открываем для редактирования файл `keycloak/values.yaml` и меняем следующие параметры на свои:

- `dockerconfigjson: []` - удалите символы `[]` и замените их на значение, которые вы получили в разделе [Создание secret для доступа в репозиторий контейнеров](#создание-secret-для-доступа-в-репозиторий-контейнеров).

> Заполняется опционально, только в том, случае, если используется приватный репозиторий. В ином случае пропустите этот шаг.

Пример заполнения:

```yaml
dockerconfigjson: eyJhdXRocyI6IHsiZG9ja2VyLnRlc3QucnUiOiB7InVzZXJuYW1lIjogImRvY2tlciIsICJwYXNzd29yZCI6ICJoVWlvNzY1NUdiZXRAT09wMDJtPT0ifX19
```

- `domain: your_domain` - заполните ваше действительное доменное имя;
- `crt:` - заполните значение `base64` `tls.crt` которое получили в разделе [Создание ключей SSL для доменных имён (SSL)](#создание-ключей-ssl-для-доменных-имён-ssl)
- `key:` - заполните значение `base64` `tls.key` которое получили в разделе [Создание ключей SSL для доменных имён (SSL)](#создание-ключей-ssl-для-доменных-имён-ssl)

- `admin_user: admin` - задайте имя пользователя для интерфейса администратора Keycloak
- `admin_password: admin` - задайте пароль пользователя для входа в интерфейс администратора Keycloak.

Следущие параметры необходимо взять из тех, что вы задали в разделе [Создание необходимых баз данных для компонентов приложения](#создание-необходимых-баз-данных-для-компонентов-приложения)

- `kc_db_url_host: 10.21.2.33` - задайте IP адрес для базы данных PostgreSQL
- `kc_db_url_port: 5433` - задайте порт для подключения к базе данных
- `kc_db_url_database: keycloak` - оставьте по умолчанию
- `kc_db_username: keycloak` - имя пользователя для доступа к базе данных Keycloak
- `kc_db_password: notpostgres` - пароль пользователя keycloak в базе данных PostgreSQL

### Листинг параметров со всеми значениями

| Параметр                         | Описание                                                                   |
| -------------------------------- | -------------------------------------------------------------------------- |
| `replicaCount`                   | Количество реплик подов, создаваемых на основе данного чарта или значения. |
| `image.repository`               | Репозиторий Docker, откуда будет загружен образ контейнера.                |
| `image.pullPolicy`               | Политика загрузки образа.                                                  |
| `image.tag`                      | Тег образа Docker, который будет использоваться.                           |
| `service.port`                   | Порт, который будет доступен снаружи для сервиса.                          |
| `service.targetport`             | Порт, на котором сервис будет работать внутри пода.                        |
| `ingress.domain`                 | Домен для Ingress контроллера.                                             |
| `ingress.crt`                    | Сертификат для TLS-терминации.                                             |
| `ingress.key`                    | Приватный ключ для TLS-терминации.                                         |
| `app.admin_user`                 | Имя пользователя администратора Keycloak.                                  |
| `app.admin_password`             | Пароль администратора Keycloak.                                            |
| `app.kc_proxy`                   | Тип прокси Keycloak.                                                       |
| `app.proxy_address_forwarding`   | Параметр для проксирования адреса.                                         |
| `app.kc_health_enabled`          | Включение или отключение health-проверок Keycloak.                         |
| `app.kc_metrics_enabled`         | Включение или отключение метрик Keycloak.                                  |
| `app.kc_http_enabled`            | Включение или отключение HTTP-поддержки Keycloak.                          |
| `app.kc_http_relative_path`      | Относительный путь для HTTP-запросов к Keycloak.                           |
| `app.kc_hostname_url_path`       | URL-путь для хостнейма Keycloak.                                           |
| `app.kc_hostname_admin_url_path` | URL-путь для административного хостнейма Keycloak.                         |
| `app.kc_db_url_host`             | Адрес хоста базы данных PostgreSQL для Keycloak.                           |
| `app.kc_db_url_port`             | Порт базы данных PostgreSQL для Keycloak.                                  |
| `app.kc_db_url_database`         | Название базы данных PostgreSQL для Keycloak.                              |
| `app.kc_db_username`             | Имя пользователя базы данных PostgreSQL для Keycloak.                      |
| `app.kc_db_password`             | Пароль пользователя базы данных PostgreSQL для Keycloak.                   |

## Применение Helm чарта

Прежде чем мы отправим чарт в кластер, надо убедиться, что чарт **валидный**. Для этого прогоним линтер:

```sh
helm lint ./keycloak
```

При желании можем посмотреть, как выглядит манифест с подставленными переменными:

```sh
helm template ./keycloak
```

Установка

```sh
helm install keycloak ./keycloak -n smart-etl
```

где:

- `keycloak` - название релиза приложения;
- `universe` - namespace, в котором будем разворачивать приложение;

### Проверка

Проверим, что появились нужные абстракции в Kubernetes:

```sh
kubectl get all -n smart-etl
```

```sh
NAME                            READY   STATUS    RESTARTS   AGE
pod/keycloak-5857d5bff9-97gfw   1/1     Running   0          21m
pod/keycloak-5857d5bff9-jv4m7   1/1     Running   0          21m
pod/keycloak-5857d5bff9-klq9q   1/1     Running   0          21m

NAME               TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)    AGE
service/keycloak   ClusterIP   None         <none>        8080/TCP   21m

NAME                       READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/keycloak   3/3     3            3           21m

NAME                                  DESIRED   CURRENT   READY   AGE
replicaset.apps/keycloak-5857d5bff9   3         3         3       21m

```

А ещё можно посмотреть информацию о шаблонах и значениях переменных, которые отправил Helm (опционально):

```sh
helm get all -n smart-etl keycloak
```

#### Доступность Keycloak

Keycloak будет доступен по адресу: `https://your-domain.local/keycloak/auth/`

### Заранее добавим клиента SAML для NiFi

Откройте конфигурационный файл клиента Keycloak который находится в `conf_keycloak/org_apache_nifi_saml_all.json` и с помощью поиска и замены замените все вхождения доменных имён на своё доменное имя.

Переходим в `https://cluster.lan/keycloak/auth/` и вводим пароль от консоли администратора, который вы указали в ConfigMap Keycloak

`Clients` -> `Import client` -> `Browse...`

- и импортируем файл.
- Сохраняем

После чего сохраняем и выходим.

### Заранее добавим клиента OIDC для NiFi-Registry

Откройте конфигурационный файл клиента Keycloak который находится в `conf_keycloak/org_apache_nifi-reg_oidc_all.json` и с помощью поиска и замены замените все вхождения доменных имён на своё доменное имя.

Переходим в `https://cluster.lan/keycloak/auth/` и вводим пароль от консоли администратора, который вы указали в ConfigMap Keycloak

`Clients` -> `Import client` -> `Browse...`

- и импортируем файл.
- Сохраняем

После чего сохраняем и выходим.

# Установка и настройка компонента NiFi

### ВАЖНО

- Не меняйте политику развёртывания StatefulSet. Особенность NiFi в том, что ноды кластера должны запускаться поочерёдно, что они и делают.
- Не меняйте имя чарта! (Файл `Chart.yaml` параметр `name: nifi`). Причины:
  - NiFi-Registry смотрит в одно и тоже хранилище ключей с NiFi. Следовательно у них один PV и PVC.
  - SSL сертификаты выпускаются для доменных имён `nifi-0.nifi.${POD_NAMESPACE}.svc.cluster.local`

## Подготовка

Для того чтобы развернуть манифесты NiFi необходимо подготовится:

- настроить NFS хранилище таким образом, чтобы в него имел доступ кластер k8s.

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

Монтируем каталог с NFS на вашу локальную машину

### Добавляем наши библиотеки и расширения в NFS хранилище

На NFS сервере предполагается, что у вас создан каталог `/var/nfs/nifi` и возможно уже успешно примонтирован (рекомендую примонтировать, чтобы убедиться в том, что с всё в порядке и вы можете работать с nfs хранилищем)

Копируем содержимое каталога `_volume_data/nifi/` в наше nfs хранилище. В итоге должна получится вот такая структура в корне NFS хранилища:

```
├── conf
│   ├── authorizers.xml
│   └── logback.xml
├── custom-libs
│   └── postgresql-42.2.2.jar
└── extensions
   └── nifi-smartetl-nar-1.0.nar
```

### Редактирование переменных Helm чарта

Открываем для редактирования файл `nifi/values.yaml` и заполняем следующие параметры:

- `dockerconfigjson: []` - удалите символы `[]` и замените их на значение, которые вы получили в разделе [Создание secret для доступа в репозиторий контейнеров](#создание-secret-для-доступа-в-репозиторий-контейнеров).

> Заполняется опционально, только в том, случае, если используется приватный репозиторий. В ином случае пропустите этот шаг.

Пример заполнения:

```yaml
dockerconfigjson: eyJhdXRocyI6IHsiZG9ja2VyLnRlc3QucnUiOiB7InVzZXJuYW1lIjogImRvY2tlciIsICJwYXNzd29yZCI6ICJoVWlvNzY1NUdiZXRAT09wMDJtPT0ifX19
```

- Зададим желаемое количество реплик NiFi в блоке:

```yaml
## Автоматическое масштабирование NiFi
hpa:
  minReplicas: 3
  maxReplicas: 3
```

- Зададим параметры Ingress для NiFi в блоке:

```yaml
ingress:
  domain: your_domain
  # base64 secret
  crt: LS0tLS1CRUdJTiBDRVJUSUZJQ0F...
  key: LS0tLS1CRUdJTiBQUkl...
```

- `domain: your_domain` - заполните ваше действительное доменное имя;
- `crt:` - заполните значение `base64` `tls.crt` которое получили в разделе [Создание ключей SSL для доменных имён (SSL)](#создание-ключей-ssl-для-доменных-имён-ssl)
- `key:` - заполните значение `base64` `tls.key` которое получили в разделе [Создание ключей SSL для доменных имён (SSL)](#создание-ключей-ssl-для-доменных-имён-ssl)

- Предоставим параметры NFS хранилища для NiFi:

```yaml
volumes:
  nfs:
    path: /var/nfs/nifi-cluster/
    server: 10.21.2.33
    storage: 30Gi
    nfsvers: "4.0"
```

где:

- `path: /var/nfs/nifi-cluster` заменим на значение каталога на NFS сервере, который настраивали в разделе [Настройка NFS](#настройка-nfs)
- `server: 10.21.2.33` - заменим на IP адрес NFS сервера;
- `storage: 30Gi` выделим необходимое количество свободного места для PV.

> Важно понимать, что лучше сразу выделять достаточно места на NFS хранилище, так как возможность расширения на данный момент отсутствует.

- Зададим параметры приложения NiFi:

`k8s_nodes: "k8s-node3.ov.universe-data.ru,k8s-node2.ov.universe-data.ru,k8s-node1.ov.universe-data.ru"` - перечислите все доменные имена нод кластера k8s (тестировалось при развёртке kubespray). Возможно при другой конфигурации кластера этот параметр заполнять не понадобится.
`keystore_password: "th1s1s3up34e5r37"` - пароль для keystore NiFi (не менее 12 символов)
`truststore_password: "th1s1s3up34e5r37"` - пароль для truststore NiFi (не менее 12 символов)

- Настроим количество реплик zookeeper:

```yaml
zookeeper:
  ### Пропишите адреса серверов в соответствии формату и количеству реплик в переменной zoo_servers, отделяя пробелом
  replicaCount: 3
  zoo_servers: "server.1=zookeeper-0.zookeeper.$(POD_NAMESPACE).svc.cluster.local:2888:3888;2181 server.2=zookeeper-1.zookeeper.$(POD_NAMESPACE).svc.cluster.local:2888:3888;2181 server.3=zookeeper-2.zookeeper.$(POD_NAMESPACE).svc.cluster.local:2888:3888;2181"
  ###
```

> ### Важно
>
> Заполните переменную zoo_server в соответствии с комментарием. Уменьшите или увеличьте количество реплик. Количесто реплик должно быть нечётным: 1,3,5 и т.д.
> Как видим, количество реплик указано 3 и в переменной zoo_servers их тоже перечилено 3.

### Листинг параметров c кратким пояснением

| Параметр                              | Описание                                                                                                                                              |
| ------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| `nifi.revisionHistoryLimit`           | Определяет максимальное количество ревизий, которые будут сохранены для истории разворачивания (Deployment).                                          |
| `nifi.podManagementPolicy`            | Управление порядком запуска подов (OrderedReady означает запускать поды по порядку и ожидать готовности каждого перед запуском следующего).           |
| `nifi.hpa.minReplicas`                | Минимальное количество реплик NiFi.                                                                                                                   |
| `nifi.hpa.maxReplicas`                | Максимальное количество реплик NiFi.                                                                                                                  |
| `nifi.image.repository`               | Репозиторий Docker-образов для NiFi.                                                                                                                  |
| `nifi.image.pullPolicy`               | Политика загрузки образа (IfNotPresent означает загрузить образ только если его нет на узле).                                                         |
| `nifi.image.tag`                      | Тег версии Docker-образа NiFi.                                                                                                                        |
| `nifi.busybox.repository`             | Репозиторий Docker-образов Busybox.                                                                                                                   |
| `nifi.busybox.tag`                    | Тег версии Docker-образа Busybox.                                                                                                                     |
| `nifi.resources.requests.cpu`         | Минимальные требования по CPU для подов NiFi.                                                                                                         |
| `nifi.resources.requests.memory`      | Минимальные требования по памяти для подов NiFi.                                                                                                      |
| `nifi.resources.limits.cpu`           | Максимальные требования по CPU для подов NiFi.                                                                                                        |
| `nifi.resources.limits.memory`        | Максимальные требования по памяти для подов NiFi.                                                                                                     |
| `nifi.resources.nifi_jvm_heap_init`   | Начальный размер кучи JVM для NiFi.                                                                                                                   |
| `nifi.resources.nifi_jvm_heap_max`    | Максимальный размер кучи JVM для NiFi.                                                                                                                |
| `nifi.service.http_port`              | Порт для HTTP-сервиса NiFi.                                                                                                                           |
| `nifi.service.https_port`             | Порт для HTTPS-сервиса NiFi.                                                                                                                          |
| `nifi.service.cluster_port`           | Порт кластера NiFi.                                                                                                                                   |
| `nifi.service.cluster_lb_port`        | Порт балансировки нагрузки кластера NiFi.                                                                                                             |
| `nifi.ingress.domain`                 | Домен, используемый для Ingress контроллера.                                                                                                          |
| `nifi.ingress.crt`                    | Сертификат TLS в формате base64 для Ingress контроллера.                                                                                              |
| `nifi.ingress.key`                    | Приватный ключ TLS в формате base64 для Ingress контроллера.                                                                                          |
| `nifi.volumes.nfs.path`               | Путь к NFS для хранения данных NiFi.                                                                                                                  |
| `nifi.volumes.nfs.server`             | Адрес сервера NFS.                                                                                                                                    |
| `nifi.volumes.nfs.storage`            | Размер хранилища NFS.                                                                                                                                 |
| `nifi.config`                         | Настройки конфигурации NiFi, включая параметры безопасности, временные интервалы и другие.                                                            |
| `zookeeper.replicaCount`              | Количество реплик Zookeeper.                                                                                                                          |
| `zookeeper.zoo_servers`               | Адреса серверов Zookeeper в соответствии с форматом и количеством реплик.                                                                             |
| `zookeeper.image.repository`          | Репозиторий Docker-образов Zookeeper.                                                                                                                 |
| `zookeeper.image.pullPolicy`          | Политика загрузки образа Zookeeper.                                                                                                                   |
| `zookeeper.image.tag`                 | Тег версии Docker-образа Zookeeper.                                                                                                                   |
| `zookeeper.podManagementPolicy`       | Управление порядком запуска подов Zookeeper (OrderedReady означает запускать поды по порядку и ожидать готовности каждого перед запуском следующего). |
| `zookeeper.service.zk_port`           | Порт Zookeeper.                                                                                                                                       |
| `zookeeper.service.http_port`         | Порт HTTP для Zookeeper.                                                                                                                              |
| `zookeeper.service.metrics_port`      | Порт метрик для Zookeeper.                                                                                                                            |
| `zookeeper.resources.requests.cpu`    | Минимальные требования по CPU для подов Zookeeper.                                                                                                    |
| `zookeeper.resources.requests.memory` | Минимальные требования по памяти для подов Zookeeper.                                                                                                 |
| `zookeeper.resources.limits.cpu`      | Максимальные требования по CPU для подов Zookeeper.                                                                                                   |
| `zookeeper.resources.limits.memory`   | Максимальные требования по памяти для подов Zookeeper.                                                                                                |
| `zookeeper.config`                    | Конфигурация Zookeeper, включая настройки автоматической очистки, метрики и другие параметры.                                                         |

## Применение Helm чарта

Прежде чем мы отправим чарт в кластер, надо убедиться, что чарт **валидный**. Для этого прогоним линтер:

```sh
helm lint ./nifi
```

При желании можем посмотреть, как выглядит манифест с подставленными переменными:

```sh
helm template ./nifi
```

Установка

```sh
helm install nifi ./nifi -n smart-etl
```

где:

- `nifi` - название релиза приложения;
- `universe` - namespace, в котором будем разворачивать приложение;

### Проверка

Проверим, что появились нужные абстракции в Kubernetes:

```sh
kubectl get all -n smart-etl
```

```sh
NAME                            READY   STATUS    RESTARTS   AGE
pod/keycloak-5857d5bff9-69m76   1/1     Running   0          4d19h
pod/keycloak-5857d5bff9-j7jhd   1/1     Running   0          4d19h
pod/keycloak-5857d5bff9-xnt9f   1/1     Running   0          4d19h
pod/nifi-0                      1/1     Running   0          4d17h
pod/nifi-1                      1/1     Running   0          4d17h
pod/nifi-2                      1/1     Running   0          4d16h
pod/zookeeper-0                 1/1     Running   0          4d17h
pod/zookeeper-1                 1/1     Running   0          4d17h
pod/zookeeper-2                 1/1     Running   0          4d17h

NAME                TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)                                AGE
service/keycloak    ClusterIP   None            <none>        8080/TCP                               4d19h
service/nifi        ClusterIP   10.233.33.181   <none>        6432/TCP,8080/TCP,8443/TCP,11443/TCP   4d17h
service/zookeeper   ClusterIP   10.233.42.210   <none>        2181/TCP,8080/TCP,7070/TCP             4d17h

NAME                       READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/keycloak   3/3     3            3           4d19h

NAME                                  DESIRED   CURRENT   READY   AGE
replicaset.apps/keycloak-5857d5bff9   3         3         3       4d19h

NAME                         READY   AGE
statefulset.apps/nifi        3/3     4d17h
statefulset.apps/zookeeper   3/3     4d17h

NAME                                       REFERENCE          TARGETS                        MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/nifi   StatefulSet/nifi   <unknown>/90%, <unknown>/90%   3         3         3          4d17h


```

А ещё можно посмотреть информацию о шаблонах и значениях переменных, которые отправил Helm (опционально):

```sh
 helm get all -n smart-etl nifi
```

#### Доступность NiFi

NiFi будет доступен по адресу: `https://your-domain.local/nifi/`. Однако, для входа в NiFi необходимо импортировать ключ в Keycloak. О чём будет написано далее.

> ### Примечание
>
> NiFi понадобится какое-то время после первого запуска, чтобы развернуть Flow. Сам сервис будет отвечать на запросы, но будет выдавать ошибку, что Flow разворачивается. Нужно просто подождать какое-то время.

# Донастройка Keycloak

## Импорт keystore

После того как NiFI развёрнётся на NFS хранилище будет создан `keystore.jks` в каталоге `keytool/all` и его необходимо импортировать в Keycloak:

- Переходим в консоль администратора Keycloak
- `Clients`
- Вкладка `Keys`
- `Import Key`
- Key alias вводим: `nifi-key`
- Ввводим пароль, который задали в `keystore_password` NiFi для Keystore.

# Установка и настройка NiFi-Registry

> **На данный момент NiFi-Registry может работать только в singe-mode. То есть запуск нескольких нод недопустим.**

Все манифесты необходмые для установки находятся по пути: `k8s-smartetl/Manifests/nifi-registry/`

Для того, чтобы установить NiFi-Registry необходимо:

- Пересобрать образ контейнера под ваше доменное имя

## Патчим Container Image под ваше доменное имя

По своей сути это нужно для того, чтобы добавить в базовый образ наш доменный сертификат ввиду того, что NiFi-Registry в отличие от NiFi не имеет опции стратегии получения доменного сертификата из keystore.

Для того, чтобы собрать образ необходимо.

1. Перети в директорию `k8s-smartetl/Manifests/nifi-registry/docker/` в которой уже находится Dockerfile с готовыми инструкциями для пересборки.

   2.1. На шаге [Создание ключей SSL для доменных имён (SSL)](#создание-ключей-ssl-для-доменных-имён-ssl) мы уже с помощью скрипта создали самоподписанный сертификат, который будет иметь имя `<ваш_домен>.сrt`.

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

### Добавляем наши библиотеки и расширения в NFS хранилище

На NFS сервере предполагается, что у вас создан каталог `/var/nfs/nifireg` и возможно уже успешно примонтирован (рекомендую примонтировать, чтобы убедиться в том, что с всё в порядке и вы можете работать с nfs хранилищем)

Копируем содержимое каталога `_volume_data/nifi-registry/` в наше NFS хранилище. В итоге должна получится вот такая структура в корне NFS хранилища:

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


### Редактирование переменных Helm чарта

Открываем для редактирования файл `nifi-registry/values.yaml`

-  `dockerconfigjson: []`  -  удалите символы `[]` и замените их на значение, которые вы получили в разделе [Создание secret для доступа в репозиторий контейнеров](#создание-secret-для-доступа-в-репозиторий-контейнеров).
> Заполняется опционально, только в том, случае, если используется приватный репозиторий. В ином случае пропустите этот шаг.

Пример заполнения:
``` yaml
  dockerconfigjson: eyJhdXRocyI6IHsiZG9ja2VyLnRlc3QucnUiOiB7InVzZXJuYW1lIjogImRvY2tlciIsICJwYXNzd29yZCI6ICJoVWlvNzY1NUdiZXRAT09wMDJtPT0ifX19
````

- Прописываем сюда пропатченный образ, который мы делалли в [Патчим Container Image под ваше доменное имя](#патчим-container-image-под-ваше-доменное-имя):

```yaml
image:
  repository: epostnikof/nifi-registry-domain
  pullPolicy: IfNotPresent
  tag: "1.24.0"
```

- Зададим параметры Ingress для NiFi-Registry в блоке:

```yaml
ingress:
  domain: your_domain
  # base64 secret
  crt: LS0tLS1CRUdJTiBDRVJUSUZJQ0F...
  key: LS0tLS1CRUdJTiBQUkl...
```

- `domain: your_domain` - заполните ваше действительное доменное имя;
- `crt:` - заполните значение `base64` `tls.crt` которое получили в разделе [Создание ключей SSL для доменных имён (SSL)](#создание-ключей-ssl-для-доменных-имён-ssl)
- `key:` - заполните значение `base64` `tls.key` которое получили в разделе [Создание ключей SSL для доменных имён (SSL)](#создание-ключей-ssl-для-доменных-имён-ssl)

- Предоставим параметры NFS хранилища для NiFi-Registry:

```yaml
volumes:
  nfs:
    path: /var/nfs/nifi-registry/
    server: 10.21.2.33
    storage: 30Gi
    nfsvers: "4.0"
```

где:

- `path: /var/nfs/nifi-registry` заменим на значение каталога на NFS сервере, который настраивали в разделе [Настройка NFS](#настройка-nfs)
- `server: 10.21.2.33` - заменим на IP адрес NFS сервера;
- `storage: 30Gi` выделим необходимое количество свободного места для PV.

> Важно понимать, что лучше сразу выделять достаточно места на NFS хранилище, так как возможность расширения на данный момент отсутствует.

- Заполним поля конфигурации, следуя комментариям:

```yaml
config:
  ### Данные должны совпадать с заданными в Helm postgresql
  postgresql_pass: notpostgres
  postgresql_ip: 10.21.2.33
  postgresql_port: "5433"
  ###############################
  ### Должны сопадать с теми, что заданы в Helm nifi (Смотрит на те же ключи, что и NiFi)
  keystore_password: "th1s1s3up34e5r37"
  truststore_password: "th1s1s3up34e5r37"
```

### Листинг параметров c кратким пояснением

Конечно, давайте добавим более подробные комментарии к описанию переменных в таблице Markdown:

| Переменная                                                   | Описание                                                                                                                                                                        |
| ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `revisionHistoryLimit`                                       | Ограничение на количество ревизий. Может быть полезно для ограничения использования ресурсов кластера.                                                                          |
| `podManagementPolicy`                                        | Политика управления Pod: `OrderedReady` - поды должны быть готовы в порядке. Позволяет управлять порядком и готовностью подов в контроллерах развертывания.                     |
| `image.repository`                                           | Репозиторий образа Docker. Определяет, откуда загружается образ.                                                                                                                |
| `image.pullPolicy`                                           | Политика загрузки образа. Определяет, когда будет загружаться образ: `Always`, `IfNotPresent`, `Never`.                                                                         |
| `image.tag`                                                  | Тег образа. Определяет конкретную версию образа для развертывания.                                                                                                              |
| `resources.requests.cpu`                                     | Запрошенные ресурсы CPU для Pod. Определяет минимальное количество CPU, необходимое для запуска контейнера.                                                                     |
| `resources.requests.memory`                                  | Запрошенная память для Pod. Определяет минимальное количество памяти, необходимое для запуска контейнера.                                                                       |
| `resources.limits.cpu`                                       | Лимиты CPU для Pod. Определяет максимальное количество CPU, которое может использовать контейнер.                                                                               |
| `resources.limits.memory`                                    | Лимиты памяти для Pod. Определяет максимальное количество памяти, которое может использовать контейнер.                                                                         |
| `service.http_port`                                          | Порт HTTP для сервиса. Определяет порт, который будет открыт для HTTP-соединений.                                                                                               |
| `service.https_port`                                         | Порт HTTPS для сервиса. Определяет порт, который будет открыт для HTTPS-соединений.                                                                                             |
| `ingress.domain`                                             | Домен для Ingress. Определяет доменное имя, по которому будет доступен сервис извне кластера.                                                                                   |
| `ingress.crt`                                                | Base64 закодированный SSL сертификат. Используется для настройки HTTPS на Ingress.                                                                                              |
| `ingress.key`                                                | Base64 закодированный приватный ключ для SSL сертификата. Используется вместе с SSL сертификатом для настройки HTTPS на Ingress.                                                |
| `volumes.nfs.path`                                           | Путь к NFS хранилищу. Определяет место, куда будет смонтировано NFS хранилище в контейнере.                                                                                     |
| `volumes.nfs.server`                                         | Сервер NFS. Определяет IP-адрес или доменное имя сервера NFS.                                                                                                                   |
| `volumes.nfs.storage`                                        | Размер хранилища NFS. Определяет доступное пространство для хранения данных в NFS.                                                                                              |
| `volumes.nfs.nfsvers`                                        | Версия NFS. Определяет версию протокола NFS для использования при монтировании NFS хранилища.                                                                                   |
| `config.postgresql_pass`                                     | Пароль для подключения к PostgreSQL. Определяет пароль для доступа к базе данных PostgreSQL.                                                                                    |
| `config.postgresql_ip`                                       | IP адрес PostgreSQL. Определяет IP-адрес сервера PostgreSQL.                                                                                                                    |
| `config.postgresql_port`                                     | Порт PostgreSQL. Определяет порт, на котором работает сервер PostgreSQL.                                                                                                        |
| `config.keystore_password`                                   | Пароль для keystore. Определяет пароль для защиты keystore, используемого для хранения ключей и сертификатов.                                                                   |
| `config.truststore_password`                                 | Пароль для truststore. Определяет пароль для защиты truststore, используемого для хранения сертификатов доверенных узлов.                                                       |
| `config.nifi_registry_security_user_oidc_discovery_url_path` | Путь к URL для обнаружения OIDC в NiFi Registry. Определяет путь к файлу с информацией об открытом OIDC в NiFi Registry.                                                        |
| `config.java_opts`                                           | Опции Java. Определяет дополнительные параметры и настройки для виртуальной машины Java, используемой для запуска NiFi-Registry.                                                |
| `config.nifi_provenance_repository_indexed_attributes`       | Атрибуты, по которым производится индексирование в репозитории происхождения NiFi. Определяет атрибуты событий, которые будут индексироваться в репозитории происхождения NiFi. |
| `config.nifi_security_user_authorizer`                       | Авторизатор пользователей безопасности NiFi. Определяет используемый в NiFi авторизатор пользователей безопасности.                                                             |
| `config.nifi_registry_security_user_oidc_connect_timeout`    | Тайм-аут подключения OIDC к NiFi Registry. Определяет максимальное время ожидания подключения к OIDC в NiFi Registry.                                                           |
| `config.nifi_registry_security_user_oidc_read_timeout`       | Тайм-аут чтения OIDC к NiFi Registry. Определяет максимальное время ожидания ответа от OIDC в NiFi Registry.                                                                    |
| `config.nifi_registry_security_user_oidc_client_id`          | Идентификатор клиента OIDC для NiFi Registry. Определяет идентиф                                                                                                                |

икатор клиента OIDC, используемый для аутентификации в NiFi Registry. |
| `config.auth` | Механизм аутентификации. Определяет используемый механизм аутентификации для доступа к NiFi-Registry, например, `basic` или `oidc`. |
| `config.initial_admin_identity` | Идентификатор начального администратора. Определяет идентификатор пользователя, который будет создан как администратор при первоначальной настройке NiFi-Registry. |

## Применение Helm чарта

Прежде чем мы отправим чарт в кластер, надо убедиться, что чарт **валидный**. Для этого прогоним линтер:

```sh
helm lint ./nifi-registry
```

При желании можем посмотреть, как выглядит манифест с подставленными переменными:

```sh
helm template ./nifi-registry
```

Установка

```sh
helm install nifi-registry ./nifi-registry -n smart-etl
```

где:

- `nifi-registry` - название релиза приложения;
- `smart-etl` - namespace, в котором будем разворачивать приложение;

### Проверка

Проверим, что появились нужные абстракции в Kubernetes:

```sh
kubectl get all -n smart-etl
```

А ещё можно посмотреть информацию о шаблонах и значениях переменных, которые отправил Helm (опционально):

```sh
 helm get all -n smart-etl nifi-registry
```

#### Доступность NiFi-Registry

NiFi будет доступен по адресу: `https://your-domain.local/nifi-registry/`

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
