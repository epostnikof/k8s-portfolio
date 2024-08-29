# Требования по утилитам

## Обязательные

Наличие следующих утилилит:

- `kubectl` - для того, чтобы следить за состоянием кластера и коррекностью установки.
- `Helm` - версия 3
- `openssl` (в случае самоподписанного сертификата) (**SSL**)
- `base64` (как правило есть в любом Linux дистрибутиве по умолчанию)
- наличие доступа в собственный репозиторий контейнеров (DockerHub, Gitlab Nexus и др. аналоги)

## k8s

- установленный плагин coreDNS
- установленный и настроенный плагин `Ingress` (**SSL**)
- (**SSL**) ноды кластера должны иметь внешнее доменное имя (CNAME на каждую ноду кластера), например:
  - `cluster-k8s.ov.universe-data.ru` `10.21.2.34` - CNAME type
  - `cluster-k8s.ov.universe-data.ru` `10.21.2.35` - CNAME type
  - `cluster-k8s.ov.universe-data.ru` `10.21.2.36` - CNAME type
  - `grafana.cluster-k8s.ov.universe-data.ru` `10.21.2.34` - CNAME type
  - `grafana.cluster-k8s.ov.universe-data.ru` `10.21.2.35` - CNAME type
  - `grafana.cluster-k8s.ov.universe-data.ru` `10.21.2.36` - CNAME type
  - `prometheus.cluster-k8s.ov.universe-data.ru` `10.21.2.34` - CNAME type
  - `prometheus.cluster-k8s.ov.universe-data.ru` `10.21.2.35` - CNAME type
  - `prometheus.cluster-k8s.ov.universe-data.ru` `10.21.2.36` - CNAME type
    где `10.21.2.34`, `10.21.2.35` и `10.21.2.36` - IP адреса нод кластера Kubernetes

### Рекомендации

- Для удобства работы с кластером рекомендуется дополнительно установить утилиту `k9s` на свою машину, с которой планируется установка, в которой достаточно просто наблюдать за процессом развёртывания. [Официальный сайт утилиты](https://k9scli.io/)

# Подготовка к установке

## Создание namespace в k8s

Для создания namespace воспользуемся следующей командой:

```sh
kubectl create namespace monitoring
```

Проверка:

```sh
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

## Настройка NFS

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
/var/nfs/grafana-data    10.0.0.0/8(rw,all_squash,no_subtree_check,nohide)
/var/nfs/prometheus-data    10.0.0.0/8(rw,all_squash,no_subtree_check,nohide)
```

В данном случае имеется общий доступ на каталог на сервере NFS:

- `/var/nfs/prometheus-data`
- `/var/nfs/grafana-data`

Да, для теста выдан доступ для целой сети `10.0.0.0/8` так как сервер k8s и ПК для разработки находятся в разных подсетях. Исключительно для удобства.

Права доступа для каталогов рекурсивно необходимо выдать так:

```sh
chown -R nobody:nogroup /var/nfs/prometheus-data && \
chown -R nobody:nogroup /var/nfs/grafana-data
```

Перезагружаем сервер nfs:

```sh
systemctl restart nfs-server
```

Монтируем каталог с NFS на вашу локальную машину

## Создание ключей SSL для доменных имён (SSL)

Предположительно сервисы мониторинга будут отзываться по отдельным доменным именам.
Например:

- `grafana.cluster-k8s.ov.universe-data.ru`
- `prometheus.cluster-k8s.ov.universe-data.ru`

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

## Мониторинг PostgreSQL и Opensearch

### Сбор метрик в PostgreSQL и Opensearch

Организация сбора метрик таких компонентов как PostgreSQL и Opensearch описана в документации: <https://confluence.unidata-platform.com/pages/viewpage.action?pageId=851181720>

# Установка Prometheus

## Подготовка

> ### Важно
>
> Так как несколько реплик Prometheus не умеют работать с одной базой данных, то было решено не поднимать более чем 1 реплику.

### Создание пространства имён

Выполните следующую команду для создания пространства имён, в котором будет располагаться приложение `Prometheus`:

```sh
kubectl create namespace monitoring
```

### Заполнение values.yaml

Helm чарт компонента `prometheus` располагается в каталоге с названием`kubertenes-prometheus`.

Откройте для редактирования любым удобным текстовым редактором файл: `kubertenes-prometheus/values.yaml`.

- `repository: docker.universe-data.ru/smart-etl/monitoring/prom/prometheus` - адрес приватного репозитория образов контейнеров;
- `tag: "latest"` - укажите нужный тэг образа контейнера backend
- `dockerconfigjson: []` - удалите символы `[]` и замените их на значение, которые вы получили в разделе [Создание secret для доступа в репозиторий контейнеров](#создание-secret-для-доступа-в-репозиторий-контейнеров). Пример заполнения:

```yaml
dockerconfigjson: eyJhdXRocyI6IHsiZG9ja2VyLnRlc3QucnUiOiB7InVzZXJuYW1lIjogImRvY2tlciIsICJwYXNzd29yZCI6ICJoVWlvNzY1NUdiZXRAT09wMDJtPT0ifX19
```

- `domain: prometheus.cluster-k8s.ov.universe-data.ru` - заполните ваше действительное доменное имя;
- `crt:` - заполните значение `base64` `tls.crt` которое получили в разделе [Создание ключей SSL для доменных имён (SSL)](#создание-ключей-ssl-для-доменных-имён-ssl)
- `key:` - заполните значение `base64` `tls.key` которое получили в разделе [Создание ключей SSL для доменных имён (SSL)](#создание-ключей-ssl-для-доменных-имён-ssl)

Укажите параметры NFS хранилища:

`nfs:`
`path: /var/nfs/prometheus-data/` - путь до сетевого каталога на NFS сервере
`server: 10.21.2.33` - IP адрес NFS сервера
`storage: 80Gi` - выделяемое пространство для метрик Prometheus (расширить без пересоздания PV и PVC нельзя. Место нужно выделить заранее с запасом)

Секцию `targets` заполните исходя из комментариев.

## Установка Helm чарта

### Установка

Прежде чем мы отправим чарт в кластер, надо убедиться, что чарт **валидный**. Для этого прогоним линтер:

```sh
helm lint ./kubertenes-prometheus
```

При желании можем посмотреть, как выглядит манифест с подставленными переменными:

```sh
helm template ./kubertenes-prometheus
```

Установка

```sh
 helm install prometheus ./kubertenes-prometheus
```

#### Проверка

Проверим, что появились нужные абстракции в Kubernetes:

```sh
kubectl get all -n monitoring
```

### Доступность сервиса

Если всё сделано правильно, то сервис будет доступен по адресу: `https://prometheus.cluster-k8s.ov.universe-data.ru`

# Установка kube-state-metrics (опционально)

## Назначение

Kube State Metrics — это сервис, который взаимодействует с сервером API Kubernetes, чтобы получить всю информацию обо всех API-объектах, таких как деплойменты, поды, daemonset, Statefulset и другие.

Основная его задача — генерировать метрики в формате Prometheus с той же стабильностью, что и API Kubernetes. В целом, он предоставляет метрики объектов и ресурсов Kubernetes, которые нельзя получить напрямую из встроенных компонентов мониторинга Kubernetes.

Сервис kube-state-metrics предоставляет все метрики на URI /metrics. Prometheus может собирать все метрики, предоставляемые kube-state-metrics.

Ниже приведены некоторые важные метрики, которые можно получить из kube-state-metrics:

- Статус узлов, емкость узлов (ЦП и память)
- Соответствие replica-set (желаемое/доступное/недоступное/обновленное состояние реплик на каждый деплоймент)
- Статус подов (ожидание, выполнение, готовность и т.д.)
- Метрики Ingress
- Метрики PV и PVC
- Метрики Daemonset и Statefulset
- Запросы и лимиты ресурсов
- Метрики задач и Cronjob

Вы можете ознакомиться с подробной документацией по поддерживаемым метрикам [здесь](https://github.com/kubernetes/kube-state-metrics/tree/main/docs).

### Заполнение values.yaml

Helm чарт компонента `prometheus` располагается в каталоге с названием`kube-state-metrics`.

Откройте для редактирования любым удобным текстовым редактором файл: `kube-state-metrics/values.yaml`.

- `repository: docker.universe-data.ru/smart-etl/monitoring/kube-state-metrics - адрес приватного репозитория образов контейнеров;
- `tag: "v.2.3.0"` - укажите нужный тэг образа контейнера backend
- `dockerconfigjson: []` - удалите символы `[]` и замените их на значение, которые вы получили в разделе [Создание secret для доступа в репозиторий контейнеров](#создание-secret-для-доступа-в-репозиторий-контейнеров). Пример заполнения:

```yaml
dockerconfigjson: eyJhdXRocyI6IHsiZG9ja2VyLnRlc3QucnUiOiB7InVzZXJuYW1lIjogImRvY2tlciIsICJwYXNzd29yZCI6ICJoVWlvNzY1NUdiZXRAT09wMDJtPT0ifX19
```

## Установка Helm чарта

### Установка

Прежде чем мы отправим чарт в кластер, надо убедиться, что чарт **валидный**. Для этого прогоним линтер:

```sh
helm lint ./kube-state-metrics
```

При желании можем посмотреть, как выглядит манифест с подставленными переменными:

```sh
helm template ./kube-state-metrics
```

Установка

```sh
 helm install prometheus ./kube-state-metrics
```

#### Проверка

Проверим, что появились нужные абстракции в Kubernetes:

```sh
kubectl get all -n monitoring
```

### Проверка установки

Зайдите в Web интерфейс Prometheus
В Web интерфейсе выберете вкладку `Status` -> `Targets`

Если всё сделано правильно, то Target `kube-state-metrics` будет иметь состояние `UP`

# Установка Node Exporter (Опционально)

## Зачем нам нужен Node Exporter в Kubernetes?

По умолчанию большинство кластеров Kubernetes предоставляет метрики сервера метрик (метрики на уровне кластера из API-резюме) и Cadvisor (метрики на уровне контейнеров). Он не предоставляет подробных метрик на уровне узлов.

Чтобы получить все системные метрики на уровне узлов Kubernetes, необходимо запускать Node Exporter на всех узлах Kubernetes. Он собирает все метрики системы Linux и предоставляет их через конечную точку /metrics на порту 9100.

Аналогично, вам нужно установить Kube State Metrics, чтобы получить все метрики, связанные с объектами Kubernetes.

### Заполнение values.yaml

Helm чарт компонента `prometheus` располагается в каталоге с названием`kubernetes-node-exporter`.

Откройте для редактирования любым удобным текстовым редактором файл: `kubernetes-node-exporter/values.yaml`.

- `repository: docker.universe-data.ru/smart-etl/monitoring/prom/node-exporter - адрес приватного репозитория образов контейнеров;
- `tag: "latest"` - укажите нужный тэг образа контейнера backend
- `dockerconfigjson: []` - удалите символы `[]` и замените их на значение, которые вы получили в разделе [Создание secret для доступа в репозиторий контейнеров](#создание-secret-для-доступа-в-репозиторий-контейнеров). Пример заполнения:

```yaml
dockerconfigjson: eyJhdXRocyI6IHsiZG9ja2VyLnRlc3QucnUiOiB7InVzZXJuYW1lIjogImRvY2tlciIsICJwYXNzd29yZCI6ICJoVWlvNzY1NUdiZXRAT09wMDJtPT0ifX19
```

## Установка Helm чарта

### Установка

Прежде чем мы отправим чарт в кластер, надо убедиться, что чарт **валидный**. Для этого прогоним линтер:

```sh
helm lint ./kubernetes-node-exporter
```

При желании можем посмотреть, как выглядит манифест с подставленными переменными:

```sh
helm template ./kubernetes-node-exporter
```

Установка

```sh
 helm install prometheus ./kubernetes-node-exporter
```

#### Проверка

Проверим, что появились нужные абстракции в Kubernetes:

```sh
kubectl get all -n monitoring
```

### Проверка установки

Зайдите в Web интерфейс Prometheus
В Web интерфейсе выберете вкладку `Status` -> `Targets`

Если всё сделано правильно, то Target `node-exporter` будет иметь состояние `UP`

# Метрики NiFi

На данном этапе у вас уже должен быть установлен NiFi. О том как это сделать описано в [документации по установке SmartETL из Helm чартов](https://git.unidata-platform.com/k8s/k8s-smartetl/-/blob/main/Helm/SmartETL/Readme.md?ref_type=heads)

Для того, чтобы NiFi начал отдавать метрики нужно включить их в UI NiFi:

Переходим в UI, по адресу который может выглядеть так: `https://cluster-k8s.ov.universe-data.ru/nifi/`

- `**burger menu**`-> `Controller Settings` -> `Report Task`
- В правом верхнем углу нажимаем `+`
- В поиске начинаем вводить `Prome`
- Найдётся `PrometheusReportingTask`
- Кликаем на него, а затем нажимаем `ADD`
- После добавления справа от `Run Status` нажимаем `Play` для запуска сборка метрик.

### Проверка выдачи метрик

Для проверки просто команду, которая сделает port-forwarding для любого из pod:

```sh
kubectl port-forward -n smart-etl nifi-0 9092:9092
```

,где

- `-n smart-etl` - это namespace в котором располагается nifi
- `9092` - порт машины и порт контейнера

После чего достаточно в веб бразуере перейти по адресу:

```ini
localhost:9092/metrics/
```

Если вы увидели метрики nifi-0 значит всё настроено верно.

### Где настроен поиск метрик для NiFi?

Откройте для просмотра файл: `kubernetes-prometheus/config-map.yaml`

и найдите `- job_name: 'nifi-pods'`

> ### Важно
>
> Kubernetes service discovery помогает Prometheus динамически добавлять новые pods. Их не нужно удалять или добавлять в конфигурации.

## Мониторинг Universe (нет)

На данный момент собственных гауджей для Prometheus у Universe пока нет.

# Установка Grafana

### Заполнение values.yaml

Helm чарт компонента `grafana` располагается в каталоге с названием`kubertenes-grafana`.

Откройте для редактирования любым удобным текстовым редактором файл: `kubertenes-grafana /values.yaml`.

- `replicaCount: 3` - укажите желаемое количество реплик
- `repository: docker.universe-data.ru/smart-etl/monitoring/grafana - адрес приватного репозитория образов контейнеров;
- `tag: "10.4.3"` - укажите нужный тэг образа контейнера backend
- `dockerconfigjson: []` - удалите символы `[]` и замените их на значение, которые вы получили в разделе [Создание secret для доступа в репозиторий контейнеров](#создание-secret-для-доступа-в-репозиторий-контейнеров). Пример заполнения:

```yaml
dockerconfigjson: eyJhdXRocyI6IHsiZG9ja2VyLnRlc3QucnUiOiB7InVzZXJuYW1lIjogImRvY2tlciIsICJwYXNzd29yZCI6ICJoVWlvNzY1NUdiZXRAT09wMDJtPT0ifX19
```

- `domain: grafana.cluster-k8s.ov.universe-data.ru` - заполните ваше действительное доменное имя;
- `crt:` - заполните значение `base64` `tls.crt` которое получили в разделе [Создание ключей SSL для доменных имён (SSL)](#создание-ключей-ssl-для-доменных-имён-ssl)
- `key:` - заполните значение `base64` `tls.key` которое получили в разделе [Создание ключей SSL для доменных имён (SSL)](#создание-ключей-ssl-для-доменных-имён-ssl)

Укажите параметры NFS хранилища:

`nfs:`
`path: /var/nfs/grafana-data/` - путь до сетевого каталога на NFS сервере
`server: 10.21.2.33` - IP адрес NFS сервера
`storage: 30Gi` - выделяемое пространство для метрик Prometheus (расширить без пересоздания PV и PVC нельзя. Место нужно выделить заранее с запасом)

## Установка Helm чарта

### Установка

Прежде чем мы отправим чарт в кластер, надо убедиться, что чарт **валидный**. Для этого прогоним линтер:

```sh
helm lint ./kubertenes-grafana
```

При желании можем посмотреть, как выглядит манифест с подставленными переменными:

```sh
helm template ./kubertenes-grafana
```

Установка

```sh
 helm install prometheus ./kubertenes-grafana
```

#### Проверка

Проверим, что появились нужные абстракции в Kubernetes:

```sh
kubectl get all -n monitoring
```

## После установки

Grafana будет доступна по адресу: `https://grafana.cluster-k8s.ov.universe-data.ru/`

Первичный логин и пароль: `admin` `admin`

По умолчанию в Data sources уже будет добавлен наш Prometheus. Проверье это зайдя в `Connections` -> `Data sources`. Перейдя в него, можно убедится, что подключение установлено успешно, нажав `Save & Test`.
Если это не так, то поправьте адрес Prometheus в настройках манифестов Prometheus.

### Добавим Dashboards

Перейдём в `Dashboards` -> `New` -> `Import`

И добавим Dashboards со следующими ID:

- Для `Node Exporter` это `1860` [ссылка на Dashboard](https://grafana.com/grafana/dashboards/1860-node-exporter-full/)
- Для `Kubernetes Deployment Statefulset Daemonset metrics` `8588` [ссылка на Dashboard](https://grafana.com/grafana/dashboards/8588-1-kubernetes-deployment-statefulset-daemonset-metrics/?tab=revisions)
- Для `NiFi` это `12314` [ссылка на Dashboard](https://grafana.com/grafana/dashboards/12314-nifi-prometheusreportingtask-dashboard/)
- Для `Zookeeper` (координатор кластера Nifi ) это `10465` (После добавления в выпадающем меню `Cluster` выбрать `zookeeper-nifi-pods`) [ссылка](https://grafana.com/grafana/dashboards/10465-zookeeper-by-prometheus/)
- Для `Keycloak` это `14390`
- Для `PostgreSQL` это `9628`
- Для `Opensearch` это `15178`

> ### Важно
>
> Не забывайте указать в качестве источника данных Prometheus

> #### Офлайн
>
> В диретории `_dashboards` лежат все необходимые дашборды, которые можно импортировать из файла

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
