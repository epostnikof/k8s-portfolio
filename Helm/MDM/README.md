---
aliases:
  - 
tags:
  - Universe
  - k8s
  - Helm
  - Kubernetes
---
# Описание

Данная конфигурация подразумевает, что хранилище данных настроено НЕ в Kubernetes, а именно такие компоненты как Opensearch и PostgreSQL.

Процесс установки будет производится с помощью Helm чартов, что несколько упрощает процесс установки в отличие от манифестов. 

Компоненты `frontend` и `backend` устанавливаются отдельно. 

Установка `frontend` предполагает один из вариантов развёртывания: 
- Установка с SSL сертификатом (`https`);
- Установка без SSL сертификата (`HTTP`). 

Для установки варианта с **SSL** требуется доменное имя и сертификат, о чём будет написано ниже.
Если вы выбираете **HTTP** установку, то доменное имя не требуется.


> [!NOTE]  ### Примечание
> Шаги с пометкой **(SSL)** можно пропускать при выборе варианта HTTP установки.

# Требования по утилитам

## Обязательные

Наличие следующих утилилит: 

- `kubectl` - для того, чтобы следить за состоянием кластера и коррекностью установки. 
- `Helm` - версия 3
- `openssl`  (в случае самоподписанного сертификата) (**SSL**)
- `base64` (как правило есть в любом Linux дистрибутиве по умолчанию)
- наличие доступа в собственный репозиторий контейнеров (DockerHub, Gitlab Nexus и др. аналоги)
## k8s 

- установленный плагин coreDNS
- установленный и настроенный плагин `Ingress` (**SSL**)
- (**SSL**) ноды кластера должны иметь внешнее доменное имя (CNAME на каждую ноду кластера), например: 
	- `cluster-k8s.ov.universe-data.ru` `10.21.2.34` - CNAME type
	- `cluster-k8s.ov.universe-data.ru` `10.21.2.35` - CNAME type
	- `cluster-k8s.ov.universe-data.ru` `10.21.2.36` - CNAME type
		где `10.21.2.34`, `10.21.2.35` и `10.21.2.36` - IP адреса нод кластера Kubernetes

### Рекомендации

- Для удобства работы с кластером рекомендуется дополнительно установить утилиту `k9s` на свою машину, с которой планируется установка, в которой достаточно просто наблюдать за процессом развёртывания. [Официальный сайт утилиты](https://k9scli.io/)

# Настройка Opensearch и PostgreSQL

Запустите сервер Opensearch и PostgreSQL любым удобным для вас методом на отдельном сервере пользуясь официальным руководством по [ссылке](https://doc.ru.universe-data.ru/6.10.0-EE/content/guides/install/index.html) (версия руководства может устареть, выберите версию пользуясь навигацией сайта)

# Подготовка к установке

## Создание namespace в k8s

Для создания namespace воспользуемся следующей командой: 

``` sh 
kubectl create namespace universe-mdm
```

Проверка: 

``` sh 
kubectl get namespaces
```

## Создание secret для доступа в репозиторий контейнеров

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

``` sh
kubectl create secret tls "example-com-tls" \
    --cert "tls.crt" \
    --key "tls.key" \
    --dry-run=client -o yaml > "secret_file.yaml"
``` 

Создасться YAML файл `secret_file.yaml`, в котором нам в дальнейшем пригодятся значения строк с ключами `tls.crt` и `tls.key`:
``` yaml
  tls.crt: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUY1RENDQTh5Z0F3SUJBZ0lVQ0hvWlVrT3JXUEN
  ...
  tls.key: LS0tLS1CRUdJTiBQUklWQVRFIEtFWS0tLS0tCk1JSUpRZ0lCQURBTkJna3Foa2lHOXcwQkFRRUZBQVN
...
```


### Кейс 2: Самоподписанный сертификат

Для использования самоподписанного сертификата и создания из него секрета необходимо воспользоваться скриптом. Скопируйте листинг данного скрипта и создайте файл `create_custom_cert.sh` со следующим содержанием:

``` sh 
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
> Замените `<your-domain>` на ваше действительное доменное имя. 

Мы создадим таким образом самоподписанные сертификаты и сразу секреты к ним cроком на 10 лет. Если сертификат нужен на более или менее продолжительный промежуток времени, то необходимо заменить этот параметр на меньшее или большее время. 

Создасться YAML файл `<your_domain>-tls.yaml`, в котором нам в дальнейшем пригодятся значения строк с ключами `tls.crt` и `tls.key`:

``` yaml
  tls.crt: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUY1RENDQTh5Z0F3SUJBZ0lVQ0hvWlVrT3JXUEN
  ...
  tls.key: LS0tLS1CRUdJTiBQUklWQVRFIEtFWS0tLS0tCk1JSUpRZ0lCQURBTkJna3Foa2lHOXcwQkFRRUZBQVN
...
```

# Установка Universe

Установка Universe MDM будет происходить по следующему сценарию: 

- Установка компонента `backend`
- Установка компонента `frontend`

## Устновка компонента backend

### Заполнение values.yaml

Helm чарт компонента `backend` располагается в каталоге с названием`universe-mdm-backend`. 

Откройте для редактирования любым удобным текстовым редактором файл: `universe-mdm-backend/values.yaml`. 

Измените значение следующих переменных: 

- `replicaCount: 3` - количество реплик pod

- `repository: docker.universe-data.ru/unidata-ee/backend` - адрес приватного репозитория образов контейнеров;
- `tag: "release-6-11-f8cef2ba"` - укажите нужный тэг образа контейнера backend 
-  `dockerconfigjson: []`  -  удалите символы `[]` и замените их на значение, которые вы получили в разделе [Создание secret для доступа в репозиторий контейнеров](#создание-secret-для-доступа-в-репозиторий-контейнеров). Пример заполнения: 
``` yaml
  dockerconfigjson: eyJhdXRocyI6IHsiZG9ja2VyLnRlc3QucnUiOiB7InVzZXJuYW1lIjogImRvY2tlciIsICJwYXNzd29yZCI6ICJoVWlvNzY1NUdiZXRAT09wMDJtPT0ifX19
```


- `postgres_address: "10.21.2.33:5432"` - адрес сервера PostgreSQL
- `postgres_username: "postgres"` - имя пользователя для авторизации на сервере PostgreSQL
-  `postgres_password: "notpostgres"` - пароль пользователя на сервере PostgreSQL
- `database_name: "universe"` - имя базы данных.
- `search_cluster_address: "10.21.2.33:9200"` - адрес кластера Opensearch;
- `search_cluster_name: "docker-cluster"` - имя кластера Opensearch;

Подробную информацию по параметрам приложения см. в официальной [документации](https://doc.ru.universe-data.ru/6.10.0-EE/content/guides/install/index.html)
### Таблица с кратким описанием всех параметров

Здесь представлена краткая справка по доступным параметрам helm чарта.

| Параметр                                 | Описание                                                                                                                                                                                                                 |
| ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `replicaCount`                           | Количество реплик подов, создаваемых на основе данного чарта или значения.                                                                                                                                               |
| `podManagementPolicy`                    | Управление порядком, в котором поды управляются контроллером развертывания. Подробности в [официальной документации k8s](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/#pod-management-policies) |
| `image.repository`                       | Репозиторий Docker, откуда будет загружен образ контейнера.                                                                                                                                                              |
| `image.tag`                              | Тег образа Docker, который будет использоваться.                                                                                                                                                                         |
| `image.pullPolicy`                       | Политика загрузки образа. Подробности в [официальной документации k8s](https://kubernetes.io/docs/concepts/containers/images/)                                                                                           |
| `backend.container_port`                 | Порт контейнера, на котором работает backend приложение.                                                                                                                                                                 |
| `backend.forward_port`                   | Порт, на который будет перенаправлен внешний трафик на порт контейнера.                                                                                                                                                  |
| `secret.dockerconfigjson`                | JSON с данными для аутентификации в Docker Registry.                                                                                                                                                                     |
| `resources.requests_ephemeral_storage`   | Запрашиваемый объем эфемерного хранилища для подов.                                                                                                                                                                      |
| `resources.limits_ephemeral_storage`     | Максимально разрешенный объем эфемерного хранилища для подов.                                                                                                                                                            |
| `config.guest_mode`                      | Режим гостя.                                                                                                                                                                                                             |
| `config.postgres_address`                | Адрес сервера PostgreSQL.                                                                                                                                                                                                |
| `config.postgres_username`               | Имя пользователя PostgreSQL.                                                                                                                                                                                             |
| `config.postgres_password`               | Пароль пользователя PostgreSQL.                                                                                                                                                                                          |
| `config.database_name`                   | Название базы данных PostgreSQL.                                                                                                                                                                                         |
| `config.search_cluster_address`          | Адрес сервера Opensearch.                                                                                                                                                                                                |
| `config.search_cluster_name`             | Название Opensearch кластера.                                                                                                                                                                                            |
| `config.email_enabled`                   | Включение или отключение отправки email уведомлений.                                                                                                                                                                     |
| `config.email_server_host`               | Хост SMTP-сервера для отправки email.                                                                                                                                                                                    |
| `config.email_server_port`               | Порт SMTP-сервера для отправки email.                                                                                                                                                                                    |
| `config.email_username`                  | Имя пользователя для аутентификации на SMTP-сервере.                                                                                                                                                                     |
| `config.email_password`                  | Пароль пользователя для аутентификации на SMTP-сервере.                                                                                                                                                                  |
| `config.email_frontend_url`              | URL фронтенда для включения в email-уведомления.                                                                                                                                                                         |
| `config.email_ssl_enable`                | Включение или отключение SSL для подключения к SMTP-серверу.                                                                                                                                                             |
| `config.email_starttls_enable`           | Включение или отключение STARTTLS для подключения к SMTP-серверу.                                                                                                                                                        |
| `config.java_tool_options`               | Опции JVM.                                                                                                                                                                                                               |
| `config.cache_auto_detection_enabled`    | Включение или отключение автоматического обнаружения кеша.                                                                                                                                                               |
| `config.cache_group`                     | Группа кеша.                                                                                                                                                                                                             |
| `config.cache_password`                  | Пароль для доступа к кешу.                                                                                                                                                                                               |
| `config.cache_port`                      | Порт кеша.                                                                                                                                                                                                               |
| `config.cache_port_autoincrement`        | Автоинкремент порта кеша.                                                                                                                                                                                                |
| `config.system_node_id`                  | Идентификатор узла системы.                                                                                                                                                                                              |
| `config.cache_public_address`            | Публичный адрес кеша.                                                                                                                                                                                                    |
| `config.tz`                              | Часовой пояс.                                                                                                                                                                                                            |
| `config.cache_kubernetes_enabled`        | Включение или отключение использования кеша Kubernetes.                                                                                                                                                                  |
| `config.cache_kubernetes_service_name`   | Имя сервиса кеша Kubernetes.                                                                                                                                                                                             |
| `config.cache_tcp_ip_enabled`            | Включение или отключение использования TCP/IP кеша.                                                                                                                                                                      |
| `config.cache_tcp_ip_members`            | Участники TCP/IP кеша.                                                                                                                                                                                                   |
| `config.cache_diagnostics_enabled`       | Включение или отключение диагностики кеша.                                                                                                                                                                               |
| `config.cache_security_recommendations`  | Рекомендации по безопасности кеша.                                                                                                                                                                                       |
| `config.cache_jet_enabled`               | Включение или отключение JET кеша.                                                                                                                                                                                       |
| `config.cache_socket_bind_any`           | Разрешение привязки сокета к любому адресу.                                                                                                                                                                              |
| `config.cache_rest_enabled`              | Включение или отключение REST-интерфейса кеша.                                                                                                                                                                           |
| `config.cache_integrity_checker_enabled` | Включение или отключение интеграционного контроля целостности кеша.                                                                                                                                                      |


### Установка

Прежде чем мы отправим чарт в кластер, надо убедиться, что чарт **валидный**. Для этого прогоним линтер:

``` sh
helm lint ./universe-mdm-backend
```

При желании можем посмотреть, как выглядит манифест с подставленными переменными:

``` sh 
helm template ./universe-mdm-backend
```

Установка 

``` sh 
helm install universe-mdm-backend ./universe-mdm-backend -n universe-mdm
```

где:
- `universe-mdm-backend` - название релиза приложения;
- `universe-mdm` - namespace, в котором будем разворачивать приложение;

#### Проверка 

Проверим, что появились нужные абстракции в Kubernetes: 

``` sh
kubectl get all -n universe-mdm
```

``` sh
NAME                         READY   STATUS    RESTARTS   AGE
pod/universe-mdm-backend-0   1/1     Running   0          18h
pod/universe-mdm-backend-1   1/1     Running   0          18h
pod/universe-mdm-backend-2   1/1     Running   0          18h

NAME                     TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
service/mdm-service      ClusterIP   10.233.6.148    <none>        5701/TCP   18h
service/mdm-ui-service   ClusterIP   10.233.25.191   <none>        9081/TCP   18h
service/ui               ClusterIP   10.233.62.161   <none>        8082/TCP   3d22h

NAME                                    READY   AGE
statefulset.apps/universe-mdm-backend   3/3     18h
```

А ещё можно посмотреть информацию о шаблонах и значениях переменных, которые отправил Helm (опционально):

``` sh
helm get all -n universe-mdm universe-mdm-backend
```

## Устновка компонента frontend

Установка frontend возможна в двух вариантах: 

- HTTP - каталог `universe-mdm-frontend-HTTP`
- SSL (HTTPS) - каталог  `universe-mdm-frontend-SSL`

> #### Выберите только один вариант установки.


Откройте для редактирования любым удобным текстовым редактором файл: `universe-mdm-frontend-HTTP/values.yaml` или `universe-mdm-frontend-SSL/values.yaml`. 

### Обязательные переменные для заполнения в обоих вариантах: 

- `replicaCount: 3` - количество реплик pod

- `repository: docker.universe-data.ru/unidata-ee/frontend - адрес приватного репозитория образов контейнеров;
- `tag: "release-6-11-df1431a6"` - укажите нужный тэг образа контейнера backend 
-  `dockerconfigjson: []`  -  удалите символы `[]` и замените их на значение, которые вы получили в разделе [Создание secret для доступа в репозиторий контейнеров](#создание-secret-для-доступа-в-репозиторий-контейнеров). Пример заполнения: 
``` yaml
  dockerconfigjson: eyJhdXRocyI6IHsiZG9ja2VyLnRlc3QucnUiOiB7InVzZXJuYW1lIjogImRvY2tlciIsICJwYXNzd29yZCI6ICJoVWlvNzY1NUdiZXRAT09wMDJtPT0ifX19
```

#### Переменные для HTTP:

Измените значение порта на котором будет доступна MDM. 
``` yaml
  ## Порт на котором будет доступна MDM по IP адресу:
  node_port: 30082
```

> MDM будет достуна по `http://<IP_aдрес_ноды_k8s_кластера>:30082`

#### Переменные для HTTPS (SSL):

- `domain: cluster-k8s.ov.universe-data.ru` - заполните ваше действительное доменное имя;
- `crt:` - заполните значение `base64` `tls.crt` которое получили в разделе [Создание ключей SSL для доменных имён (SSL)](#создание-ключей-ssl-для-доменных-имён-ssl)
-  `key:` - заполните значение `base64` `tls.key` которое получили в разделе [Создание ключей SSL для доменных имён (SSL)](#создание-ключей-ssl-для-доменных-имён-ssl)


### Таблица с кратким описанием всех параметров

| Параметр                               | Описание                                                                   |
| -------------------------------------- | -------------------------------------------------------------------------- |
| `replicaCount`                         | Количество реплик подов, создаваемых на основе данного чарта или значения. |
| `image.repository`                     | Репозиторий Docker, откуда будет загружен образ контейнера.                |
| `image.tag`                            | Тег образа Docker, который будет использоваться.                           |
| `image.pullPolicy`                     | Политика загрузки образа.                                                  |
| `frontend.container_port`              | Порт контейнера, на котором работает frontend приложение.                  |
| `frontend.forward_port`                | Порт, на который будет перенаправлен внешний трафик на порт контейнера.    |
| `frontend.node_port`                   | Порт, на котором будет доступна MDM по IP адресу.                          |
| `secret.dockerconfigjson`              | JSON с данными для аутентификации в Docker Registry.                       |
| `resources.requests_ephemeral_storage` | Запрашиваемый объем эфемерного хранилища для подов.                        |
| `resources.limits_ephemeral_storage`   | Максимально разрешенный объем эфемерного хранилища для подов.              |
| `ingress.domain`                       | Домен для Ingress контроллера.                                             |
| `ingress.crt`                          | Сертификат для TLS-терминации.                                             |
| `ingress.key`                          | Приватный ключ для TLS-терминации.                                         |

### Установка 

Прежде чем мы отправим чарт в кластер, надо убедиться, что чарт **валидный**. Для этого прогоним линтер:

``` sh
helm lint ./universe-mdm-frontend-SSL
```

При желании можем посмотреть, как выглядит манифест с подставленными переменными:

``` sh 
helm template ./universe-mdm-frontend-SSL
```

Установка 

``` sh 
helm install universe-mdm-frontend ./universe-mdm-frontend-SSL -n universe-mdm
```

где:
- `universe-mdm-frontend` - название релиза приложения;
- `universe-mdm` - namespace, в котором будем разворачивать приложение;

#### Проверка 

Проверим, что появились нужные абстракции в Kubernetes: 

``` sh
kubectl get all -n universe-mdm
```

``` sh
NAME                                         READY   STATUS    RESTARTS   AGE
pod/universe-mdm-backend-0                   1/1     Running   0          19h
pod/universe-mdm-backend-1                   1/1     Running   0          19h
pod/universe-mdm-backend-2                   1/1     Running   0          19h
pod/universe-mdm-frontend-5878bf78ff-c4mjl   1/1     Running   0          22s
pod/universe-mdm-frontend-5878bf78ff-m5j9x   1/1     Running   0          22s
pod/universe-mdm-frontend-5878bf78ff-pvp8f   1/1     Running   0          22s

NAME                                    TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
service/mdm-service                     ClusterIP      10.233.6.148    <none>        5701/TCP       19h
service/mdm-ui-service                  ClusterIP      10.233.25.191   <none>        9081/TCP       19h
service/ui                              ClusterIP      10.233.62.161   <none>        8082/TCP       3d22h
service/universe-mdm-frontend-service   LoadBalancer   10.233.9.184    <pending>     80:30095/TCP   23s

NAME                                    READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/universe-mdm-frontend   3/3     3            3           24s

NAME                                               DESIRED   CURRENT   READY   AGE
replicaset.apps/universe-mdm-frontend-5878bf78ff   3         3         3       23s

NAME                                    READY   AGE
statefulset.apps/universe-mdm-backend   3/3     19h
```

А ещё можно посмотреть информацию о шаблонах и значениях переменных, которые отправил Helm (опционально):

``` sh
helm get all -n universe-mdm universe-mdm-frontend
```

#### Доступность MDM

Для `HTTP`: `http://<IP_aдрес_ноды_k8s_кластера>:30082` 

Для `HTTPS`: `https://your-domain.local`

## Дополнительные команды Helm 

### Выпуск нового релиза

Чтобы выпустить новый релиз, нам нужно сделать хотя бы одну из 2 вещей, но можно и обе:

1. Поменять в `Chart.yaml` значение у `version`.
2. Внести какие-то изменения в шаблоны/значения.

А после отправить новую версию чарта в кластер:

```sh
helm upgrade <name> ./<chart_name>
```

```bash
$ helm upgrade  nginx ./nginx-test

Release "nginx" has been upgraded. Happy Helming!
NAME: nginx
LAST DEPLOYED: <date>
NAMESPACE: default
STATUS: deployed
REVISION: 2
TEST SUITE: None
```

Новой назовём условно, потому что версия чарта может не измениться, но, к примеру, изменится образ внутри чарта или версия приложения. В идеальном мире при любых изменениях в чарте будет изменена версия чарта, но это не всегда происходит так

На самом деле, если ничего не изменить в чарте и сделать `upgrade`, в Helm появится новый релиз, при этом в кластере Kubernetes ничего не произойдёт с абстракциями из манифеста.

Немного полезностей, которые помогут при работе:

- Ключи `--wait` и `--timeout 600` могут быть очень полезны при работе, они в паре говорят `Helm` подождать ответа от `Kubernetes` 10 минут (600 секунд) вместо 5 минут по умолчанию. Время ожидания может зависеть от специфики кластера или пайплайна развёртки вашего приложения, можно изменять.
- Взять текущие переменные, которые использовались в чарте -> поменять значения переменных (если нужно) -> обновить релиз с новыми значениями из файла:

```sh
  helm get values nginx > my.values
  helm upgrade nginx./nginx-test --values my.values
```

Ключ `--reuse-values` говорит `Helm` использовать при обновлении значения переменных из последнего релиза.

---

#### 

Как проверить в Kubernetes, что установлен новый релиз

- Выполнить `helm list`, посмотреть список установленных релизов и время их жизни
- Выполнить `kubectl descibe <resource> <resource_name` для того ресурса, который изменяли, и убедиться, что стоят новые значения

---

### 

Откат на предыдущую версию релиза

Помнишь я говорил, что Helm позволяет откатиться на предыдущий релиз? Давай попробуем это сделать

Чтобы показать **rollback** более наглядно, создадим три релиза:

1. Собственно, тот, что мы создали раньше.
2. Изменим `service.port` в `values.yaml` с `80` на `8080` и сделаем `helm upgrade`.
3. Изменим версию чарта в `<chart_name>/Chart.yaml` на 0.0.2 (переменная `version`), тоже задеплоим в кластер с помощью `helm upgrade`.

> А где Helm должен хранить информацию о релизах?

### 

Как просмотреть информацию о релизах:

```sh
helm history <name> 
```

```sh
$ helm history nginx

REVISION    UPDATED     STATUS          CHART            APP VERSION    DESCRIPTION
1           <date>      superseded      nginx-0.0.1      1.0            Install complete
2           <date>        superseded      nginx-0.0.1      1.0            Upgrade complete
3           <date>        deployed        nginx-0.0.2      1.0            Upgrade complete
```

Откатимся на 1 релиз:

```sh
helm rollback <name> revision_number
```

```sh
helm rollback nginx 1

Rollback was a success! Happy Helming!
```

При **rollback** создаётся новый релиз:

```sh
$ helm history nginx   
  
REVISION    UPDATED     STATUS             CHART            APP VERSION    DESCRIPTION
1           <date>        superseded      nginx-0.0.1      1.0            Install complete
2           <date>        superseded         nginx-0.0.1      1.0            Upgrade complete
3           <date>        superseded         nginx-0.0.2      1.0            Upgrade complete
4           <date>        deployed        nginx-0.0.1      1.0            Rollback to 1
```

### 

Удалить релиз

Для уничтожения релиза используем:

```sh
helm uninstall <name>
```

Если дописать ключ `--keep-history`, то история релизов останется и можно будет применить **rollback**, иначе удалится вся информация о релизе.

```sh
$ helm uninstall nginx --keep-history

release "nginx" uninstalled
```

Проверим, что вся информация о релизе сохранилась (спасибо ключу `--keep-history`), и релиз больше не считается установленным:

```sh
helm history nginx    

REVISION    UPDATED     STATUS           CHART            APP VERSION    DESCRIPTION
1           <date>        superseded       nginx-0.0.1      1.0            Install complete
2           <date>        superseded       nginx-0.0.1      1.0            Upgrade complete
3           <date>        superseded       nginx-0.0.2      1.0            Upgrade complete
4           <date>        uninstalled      nginx-0.0.1      1.0            Uninstallation complete
```

---

Как можно откатить изменения в Kubernetes кластере без сторонних средств?

Использовать `kubectl rollout undo`  
Создавать копию шаблонизированных манифестов и значений перед изменениями

## Полезные ресурсы

[Шпаргалка по Helm](https://helm.sh/docs/intro/cheatsheet/)
