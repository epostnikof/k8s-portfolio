# Описание

Данная конфигурация подразумевает, что хранилище данных настроено НЕ вKubernetes, а именно такие компоненты как Opensearch и PostgreSQL.

# Требования по утилитам

## Обязательные

Наличие следующих утилилит:

- `kubectl`
- наличие доступа в собственный репозиторий контейнеров (DockerHub, Gitlab Nexus и др. аналоги)

## k8s

- установленный плагин coreDNS


### Рекомендации

- Для удобства работы с кластером рекомендуется дополнительно установить утилиту `k9s` на свою машину, с которой планируется установка, в которой достаточно просто наблюдать за процессом развёртывания. [Официальный сайт утилиты](https://k9scli.io/)

# Настройка Opensearch и PostgreSQL

Запустите сервер Opensearch и PostgreSQL любым удобным для вас методом на отдельном сервере пользуясь официальным руководством по [ссылке](https://doc.ru.universe-data.ru/6.10.0-EE/content/guides/install/index.html) (версия руководства может устареть, выберите версию пользуясь навигацией сайта)

# Установка Universe

Установка будет проводится в отдельный namespace k8s под названием `universe-mdm`

## Создание namespace в k8s

Для создания namespace воспользуемся следующей командой:

```sh
kubectl create namespace universe-mdm
```

Проверка:

```sh
kubectl get namespaces
```

### Если имя вашего namespace отличается от предложенного

Необходимо открыть для редактирования файл `Manifests/MDM/Manifests/not_SSL/hazelcast-cluster-role-binding.yaml`

и отредактировать поле: `namespace: universe-mdm` , поменяв значение `universe-mdm` на своё.

## Правка secret.yaml

Файл `secret.yaml` нужен для определения Secret, содержащего данные для доступа к Docker registry.

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

Таким образом мы получим значение `base64` для доступа к Docker registry

Далее открываем для редактирования файл: `Manifests/MDM/Manifests/not_SSL/secret.yml`

И вставляем значение `base64` в секции:

```yaml
data:
  .dockerconfigjson: <put_your_base64_secret_here>
```

где `<put_your_base64_secret_here>` заменим на получившиеся значение `base64`. Пример готового результата:

```yaml
data:
  .dockerconfigjson: eyJhdXRocyI6IHsiZG9ja2VyLnRlc3QucnUiOiB7InVzZXJuYW1lIjogImRvY2tlciIsICJwYXNzd29yZCI6ICJoVWlvNzY1NUdiZXRAT09wMDJtPT0ifX19
```

Сохраняем.

## Правка ConfigMap для backend

Открываем для редактирования файл: `Manifests/MDM/Manifests/not_SSL/config-map-be.yaml`

Блок необходимых настроек, которые нужно редактировать:

```yaml
POSTGRES_ADDRESS: "10.21.2.33:5432"
POSTGRES_USERNAME: "postgres"
POSTGRES_PASSWORD: "notpostgres"
DATABASE_NAME: "universe"
SEARCH_CLUSTER_ADDRESS: "10.21.2.33:9200"
SEARCH_CLUSTER_NAME: "docker-cluster"
```

где:

`POSTGRES_ADDRESS:` - адрес сервера PostgreSQL
`POSTGRES_USERNAME:` - имя пользователя для базы данных PostgreSQL
`POSTGRES_PASSWORD:` - пароль для доступа к PostgreSQL
`DATABASE_NAME:` - имя базы данных для MDM Universe
`SEARCH_CLUSTER_ADDRESS:` - адрес для доступа к Opensearch
`SEARCH_CLUSTER_NAME`: имя кластера Opensearch

## Приминение манифеста

- Перейдите в каталог `Manifests/MDM/Manifests`
- Выполните команду:

```sh
kubectl apply -f ./not_SSL -n universe-mdm
```

, где `universe-mdm` - имя вашего namespace. Если оно отличается, укажите своё.

### Как понять, что кластер развернулся корректно

Откройте для чтения логи любого из pod backend командой:

```sh
kubectl logs -f -n universe-mdm mdm-deployment-0
```

, где `universe-mdm` замените на имя вашего namespace

если кластер собирается правильно, то в логах будут появляться сообщения о новых участниках кластера. Пример таких сообщений ниже:

```log
02-May-2024 15:17:48.101 INFO [hz.unidata.IO.thread-in-1] com.hazelcast.internal.server.tcp.TcpServerConnection.null [10.233.102.165]:5701 [dev] [5.3.6] Initialized new cluster connection between /10.233.102.165:5701 and /10.233.102.171:57517
02-May-2024 15:17:53.213 INFO [hz.unidata.priority-generic-operation.thread-0] com.hazelcast.internal.cluster.ClusterService.null [10.233.102.165]:5701 [dev] [5.3.6]

Members {size:5, ver:5} [
        Member [10.233.102.165]:5701 - ca9540fb-2b57-4066-809d-721975ef2979 this
        Member [10.233.75.57]:5701 - 8f55a5f5-1e56-492e-9a26-32fd4d1de8f4
        Member [10.233.71.37]:5701 - ae8a21d1-7846-4078-a7b5-2502caa93d2c
        Member [10.233.75.59]:5701 - 2e6afdac-9bdc-4017-b945-a574c5ea7dc0
        Member [10.233.102.171]:5701 - 41a99482-42f1-425e-b23b-96ee4ad98217
]

```

> Лог при масштабировании backend до 5 участников кластера

## Доступность Universe MDM

Universe MDM будет доступна по адресу: `<ваш_домен_или_IP>:30082`

В данном случае (см. требования) MDM доступна по адресу: `cluster-k8s.ov.universe-data.ru:30082`

Для авторизации введите:

логин: `admin`
пароль: `admin`

После чего установите файл лицензии и задайте свой пароль администратора.

# После развертывания

### Масштабирование

Масштабирование приложения можно произвести двумя способами:

1. В файлах манифеста (рекомендуется)
2. С помощью утилилиты `kubectl`, выполнив команду

> ### Важно
>
> Политика развёртывания pod'ов для backend установлена как `podManagementPolicy: OrderedReady` - это означает, что pods будут разворачиваться друг за другом. То есть, пока первый pod не запуститься полностью, то второй pod не запуститься. Это нужно, для более стабильной развёртки кластера.

#### Масштабирование с помощью файлов манифеста

Для масштабирования одного любого из частей приложения откройте следующий файл для редактирования:

Для **Backend**: `Manifests/MDM/Manifests/not_SSL/mdm-statefulset.yaml`

Для **Frontend**: `Manifests/MDM/Manifests/not_SSL/ui-deployment.yaml`

И в каждом из файлов замените значение поля `replicas` на своё.

**Пример:**

```yaml
replicas: 3
```

Это означает, что у приложения будут запущены 3 реплики.

После сохранения файла с новым значением примените манифест:

```sh
kubectl apply -f ./not_SSL -n universe-mdm
```

, где `universe-mdm` - имя вашего namespace. Если оно отличается, укажите своё.

#### Масштабирование с помощью команд

Данный способ масштабирования рекомендуется только в случае отладки. Так как при внесении изменений в манифесты может оказаться так, что вы забудете указать требуемое количество реплик pod и они неожиданным образом увеличаться или уменьшаться.

Для масштабирования **backend** выполните команду:

```sh
kubectl -n universe-mdm scale statefulset mdm-deployment --replicas=3
```

, где

- `universe-mdm` - пространство имён, в котором находится statefulset
- `--replicas=3` - желаемое количество реплик pod.

> Масштабирование можно производить как вверх так и вниз.

Для масштабирования **frontend** выполните команду:

```sh
kubectl -n universe-mdm scale deployment ui-deployment --replicas=5
```

, где

- `universe-mdm` - пространство имён, в котором находится statefulset
- `--replicas=3` - желаемое количество реплик pod.

> Масштабирование можно производить как вверх так и вниз.

### Обновление

Перед обновлением удостоверьтесь, что вы настроили `secret.yml` (см. описание выше) для доступа к Docker Registry.

Проверить наличие secret можно командой:

```sh
kubectl -n universe-mdm get secrets
```

, где `universe-mdm` - имя вашего namespace в котором работает Universe MDM

Корректный вывод:

```
NAME         TYPE                             DATA   AGE
my-regcred   kubernetes.io/dockerconfigjson   1      16h
```

Имя secret `my-regcred`. Если с этим secret не было проблем с установкой MDM, то и не должно быть с обновлением.

#### Обновление без остановки pod

> ### Важно
>
> Обновление backend будет производиться от последнего pod к 1. Постепенно. Это означает, что во время обнолвления сначала остановиться pod с наивышим индексом, обновиться, запустится и т.д. До успешного завершения обнолвения балансировшик не будет пускать на него трафик.
> Однако данный способ обновления требует тщательного тестирования и возможно не является безопасным.
> Для обеспечения надёжности рекомендуется удалить все pod и произвести развёртку с 0 (см. раздел "Обновление с полной остановкой pod".

Для обноления одного любого из частей приложения откройте следующий файл для редактирования:

Для **Backend**: `Manifests/MDM/Manifests/not_SSL/mdm-statefulset.yaml`

Для **Frontend**: `Manifests/MDM/Manifests/not_SSL/ui-deployment.yaml`

И замените ссылку до базового образа в секции:

Для **backend**:

```yaml
image: docker.universe-data.ru/unidata-ee/backend:release-6-11-ff95d77a
```

Для **frontend**:

```yaml
image: docker.universe-data.ru/unidata-ee/frontend:release-6-11-fc8c0c26
```

- Сохраните файлы.

- Перейдите в каталог `Manifests/MDM/Manifests`

- Выполните команду:

```sh
kubectl apply -f ./not_SSL -n universe-mdm
```

, где `universe-mdm` - имя вашего namespace. Если оно отличается, укажите своё.

#### Обновление с полной остановкой pod

Для обноления одного любого из частей приложения откройте следующий файл для редактирования:

Для **Backend**: `Manifests/MDM/Manifests/not_SSL/mdm-statefulset.yaml`

Для **Frontend**: `Manifests/MDM/Manifests/not_SSL/ui-deployment.yaml`

И замените ссылку до базового образа в секции:

Для **backend**:

```yaml
image: docker.universe-data.ru/unidata-ee/backend:release-6-11-ff95d77a
```

Для **frontend**:

```yaml
image: docker.universe-data.ru/unidata-ee/frontend:release-6-11-fc8c0c26
```

- Сохраните файлы.

- Перейдите в каталог `Manifests/MDM/Manifests`

- Выполните команду для удаления работающего MDM в k8s:

```sh
kubectl delete -f ./not_SSL -n universe-mdm
```

, где `universe-mdm` - имя вашего namespace. Если оно отличается, укажите своё.

- Выполните команду для применения новых манифестов MDM:

```sh
kubectl apply -f ./not_SSL -n universe-mdm
```

> ### Примечание
>
> Во избежании потери каких-либо конфигураций. Все изменения в конфигурацию рекомендуется вносить именно в **манифесты**, а не работая напрямую с API Kubernetes такими командами как \`kubectl -n universe-mdm scale deployment ui-deployment --replicas=5.
> Это связано с тем, что применение манифеста затирает собой изменённую вами конфигурацию с помощью команд.
