## Важно

Манифесты являются неким прогоном, перед созданием Helm чартов.
В манифестах нет привязки к NFS хранилищу, поэтому здесь хранение данных происходит в emptyDir - это означает, что при перезапуске pod все данные pod удаляются.

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

# Установка Prometheus

## Создание пространства имён

Выполните следующую команду для создания пространства имён, в котором будет располагаться приложение `Prometheus`:

```sh
kubectl create namespace monitoring
```

## Указываем на количество реплик подов Prometheus

Отройте для редактирования файл: `kubernetes-prometheus/prometheus-deployment.yaml` и внесите изменения в следущие секции:

```yaml
spec:
  replicas: 1
```

где, вместо 1, укажите желаемое количество реплик Prometheus

## Задание доменного имени и сертификата

Отройте для редактирования файл: `kubernetes-prometheus/prometheus-ingress.yaml` и внесите изменения в следущие секции:

Укажите ваше действительное доменное имя, вместо того, что присутствует в манифесте:

```yaml
- host: prometheus.cluster-k8s.ov.universe-data.ru
```

и здесь

```yaml
tls:
  - hosts:
      - prometheus.cluster-k8s.ov.universe-data.ru
```

Укажите `tls.crt` и `tls.key` вместо существующих для домена в формате base64, который мы сгенерировали на шаге [Создание ключей SSL для доменных имён (SSL)](#создание-ключей-ssl-для-доменных-имён-ssl):

```yaml
data:
  # USe base64 in the certs
  tls.crt: LS0tLS1CRUdJTiBDRVJUSUZJQ0...
  tls.key: LS0tLS1CRUdJTiBQUklWKJKDfj...
```

## Собственная конфигурация Prometheus

Если требуется задайте собственную конфигурацию prometheus в файле `kubernetes-prometheus/config-map.yaml`

## Применение манифеста

Примените манифест командой:

```sh
kubectl apply -f ./kubernetes-prometheus
```

> ### Важно
>
> Манифесты написаны для пространства имён `monitoring` и применятся к нему

Проверьте корректность установки командой:

```sh
kubectl get deployments --namespace=monitoring
```

### Доступность сервиса

Если всё сделано правильно, то сервис будет доступен по доменному имени: `https://prometheus.cluster-k8s.ov.universe-data.ru/`

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

## Установка

Для установки выполните команду:

```sh
kubectl apply -f kube-state-metrics-configs/
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

## Установка

Для установки выполните команду:

```sh
kubectl apply -f ./kubernetes-node-exporter
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

## Мониторинг PostgreSQL и Opensearch

### Сбор метрик в PostgreSQL и Opensearch

Организация сбора метрик таких компонентов как PostgreSQL и Opensearch описана в документации: <https://confluence.unidata-platform.com/pages/viewpage.action?pageId=851181720>

### Добавляем Job для сбора метрик в конфигурацию манифеста k8s

Откройте для редактирования файл: `kubernetes-prometheus/config-map.yaml`

Найдите секции: `- job_name: postgres-endpoint` и `- job_name: opensearch`
В каждой секции измените значение на свой IP адрес:

```
        - targets:
          - 10.21.2.33:9200
```

# Установка Grafana

## Указываем на количество реплик подов Grafana

Отройте для редактирования файл: `kubernetes-grafana/deployment.yaml` и внесите изменения в следущие секции:

```yaml
spec:
  replicas: 1
```

где, вместо 1, укажите желаемое количество реплик Prometheus

## Задание доменного имени и сертификата

Отройте для редактирования файл: `kubernetes-grafana/grafana-ingress.yaml` и внесите изменения в следущие секции:

Укажите ваше действительное доменное имя, вместо того, что присутствует в манифесте:

```yaml
- host: grafana.cluster-k8s.ov.universe-data.ru
```

и здесь

```yaml
tls:
  - hosts:
      - grafana.cluster-k8s.ov.universe-data.ru
```

Укажите `tls.crt` и `tls.key` вместо существующих для домена в формате base64, который мы сгенерировали на шаге [Создание ключей SSL для доменных имён (SSL)](#создание-ключей-ssl-для-доменных-имён-ssl):

```yaml
data:
  # USe base64 in the certs
  tls.crt: LS0tLS1CRUdJTiBDRVJUSUZJQ0...
  tls.key: LS0tLS1CRUdJTiBQUklWKJKDfj...
```

## Применение манифеста

Примените манифест командой:

```sh
kubectl apply -f ./kubernetes-grafana
```

> ### Важно
>
> Манифесты написаны для пространства имён `monitoring` и применятся к нему

Проверьте корректность установки командой:

```sh
kubectl get deployments --namespace=monitoring
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
- Для `Keycloak` это `10441` [ссылка](https://grafana.com/grafana/dashboards/10441-keycloak-metrics-dashboard/)
- Для `PostgreSQL` это `9628`
- Для `Opensearch` это `15178`

> ### Важно
>
> Не забывайте указать в качестве источника данных Prometheus

> #### Офлайн
>
> В диретории `_dashboards` лежат все необходимые дашборды, которые можно импортировать из файла
