# Описание

Blue/Green Deployment (развертывание "синий/зеленый") — это метод развертывания приложений, который позволяет минимизировать время простоя и риски, связанные с обновлениями. В контексте Kubernetes, эта стратегия подразумевает наличие двух идентичных окружений: **Blue** (синий) и **Green** (зеленый).

### Как это работает

1. **Текущая версия (Blue)**:

   - В текущий момент приложение работает в окружении Blue.
   - Все пользователи и трафик направляются к версиям сервисов, развернутым в этом окружении.

2. **Новая версия (Green)**:

   - Новая версия приложения разворачивается в окружении Green.
   - Окружение Green полностью дублирует окружение Blue, но включает обновленные версии приложений или сервисов.

3. **Тестирование**:

   - После развертывания новой версии в окружении Green, оно тестируется для проверки корректности работы.
   - Проводятся различные тесты: функциональные, интеграционные, нагрузочные и т.д.

4. **Переключение трафика**:

   - После успешного тестирования вся нагрузка (пользовательский трафик) перенаправляется с окружения Blue на Green.
   - В Kubernetes это может быть реализовано через изменение конфигурации сервиса, обновление меток (labels) или изменение конфигурации ingress контроллера.

5. **Старое окружение (Blue)**:

   - Окружение Blue остается в рабочем состоянии на случай необходимости отката (rollback).
   - Если возникают проблемы с окружением Green, можно быстро переключиться обратно на Blue, минимизируя простои и риски.

6. **Удаление старой версии**:

   - После успешного перехода на новую версию и отсутствия проблем в течение определенного времени, старое окружение Blue можно удалить или подготовить для следующего цикла обновлений.

### Преимущества Blue/Green Deployment

- **Минимизация времени простоя**: Обновления происходят без прерывания текущего сервиса.
- **Безопасность отката**: В случае проблем с новой версией можно быстро вернуться к предыдущей стабильной версии.
- **Тестирование в продакшен окружении**: Новая версия тестируется в условиях, максимально приближенных к боевым.

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
  - `blue-green.cluster-k8s.ov.universe-data.ru` `10.21.2.34` - CNAME type
  - `blue-green.cluster-k8s.ov.universe-data.ru` `10.21.2.35` - CNAME type
  - `blue-green.cluster-k8s.ov.universe-data.ru` `10.21.2.36` - CNAME type
    где `10.21.2.34`, `10.21.2.35` и `10.21.2.36` - IP адреса нод кластера Kubernetes

> Доменное имя `blue-green.cluster-k8s.ov.universe-data.ru` необходимо для реализации blue/green стратегии обновления Frontend

### Рекомендации

- Для удобства работы с кластером рекомендуется дополнительно установить утилиту `k9s` на свою машину, с которой планируется установка, в которой достаточно просто наблюдать за процессом развёртывания. [Официальный сайт утилиты](https://k9scli.io/)

# Первичная развертка

Здесь описывается процесс развертки на пустой кластер, на котором ещё нет компонентов MDM. Если вас интересует обнвовление то переходите в раздел [Обновление](#обновление)

Перед первичной развёрткой убедитесь, что ещё нет установленных Helm чартов с MDM с помощью команды:

```sh
helm list --all-namespaces
```

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

> ### Важно
>
> Для реализации blue/green стратегии нужно дополнительное тестовое доменное имя для тестирования frontend (см. требования вначале)

## Создание secret для доступа в репозиторий контейнеров

Прежде всего, для того, чтобы Kubernetes мог скачать образы контейнеров необходимо указать ему данные для авторизации в формате `base64`

Для получения `<base64-encoded-json>`, необходимо выполнить команду:

```
echo -n '{"auths": {"docker.test.ru": {"username": "docker", "password": "hUio7655Gbet@OOp02m=="}}}' | base64
```

,где  
**Адрес Docker registry**: `docker.test.ru`  
**Пользователь**: `docker`  
**Пароль**: `hUio7655Gbet@OOp02m==`

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

Таким образом мы получим значение `base64` для доступа к Docker registry.

Сохраните это значение в отдельный файл, чтобы позже скопировать его.

За дополнительной информацией обратитесь к официальной [документации](https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/)

## Backend

### Создание пространства имён

Развёртка будет происходить в пространстве имён `universe-mdm`.
Создадим пространство имён командой:

```sh
kubectl create namespace universe-mdm
```

### Разворачиваем blue чарт

Helm чарт компонента `backend` располагается в каталоге с названием`universe-mdm-backend-blue`.

Откройте для редактирования любым удобным текстовым редактором файл: `universe-mdm-backend-blue/values.yaml`.

Измените значение следующих переменных:

- `replicaCount: 3` - количество реплик pod

- `repository: docker.universe-data.ru/unidata-ee/backend` - адрес приватного репозитория образов контейнеров;

- `tag: "release-6-11-f8cef2ba"` - укажите нужный тэг образа контейнера backend

> ### Важно
>
> Не забудьте отредактировать значение образа в `universe-mdm-frontend-SSL-blue/Chart.yaml` в строке `appVersion: "release-6-11-df1431a6"` во избежании путаницы в образах.

- `dockerconfigjson: []` - удалите символы `[]` и замените их на значение, которые вы получили в разделе [Создание secret для доступа в репозиторий контейнеров](app://obsidian.md/index.html#%D1%81%D0%BE%D0%B7%D0%B4%D0%B0%D0%BD%D0%B8%D0%B5-secret-%D0%B4%D0%BB%D1%8F-%D0%B4%D0%BE%D1%81%D1%82%D1%83%D0%BF%D0%B0-%D0%B2-%D1%80%D0%B5%D0%BF%D0%BE%D0%B7%D0%B8%D1%82%D0%BE%D1%80%D0%B8%D0%B9-%D0%BA%D0%BE%D0%BD%D1%82%D0%B5%D0%B9%D0%BD%D0%B5%D1%80%D0%BE%D0%B2). Пример заполнения:

```yaml
dockerconfigjson: eyJhdXRocyI6IHsiZG9ja2VyLnRlc3QucnUiOiB7InVzZXJuYW1lIjogImRvY2tlciIsICJwYXNzd29yZCI6ICJoVWlvNzY1NUdiZXRAT09wMDJtPT0ifX19
```

- `postgres_address: "10.21.2.33:5432"` - адрес сервера PostgreSQL
- `postgres_username: "postgres"` - имя пользователя для авторизации на сервере PostgreSQL
- `postgres_password: "notpostgres"` - пароль пользователя на сервере PostgreSQL
- `database_name: "universe"` - имя базы данных.
- `search_cluster_address: "10.21.2.33:9200"` - адрес кластера Opensearch;
- `search_cluster_name: "docker-cluster"` - имя кластера Opensearch;

Подробную информацию по параметрам приложения см. в официальной [документации](https://doc.ru.universe-data.ru/6.10.0-EE/content/guides/install/index.html)

### Установка

Прежде чем мы отправим чарт в кластер, надо убедиться, что чарт **валидный**. Для этого прогоним линтер:

```sh
helm lint ./universe-mdm-backend-blue
```

При желании можем посмотреть, как выглядит манифест с подставленными переменными:

```sh
helm template ./universe-mdm-backend-blue
```

Установка

```sh
helm install universe-mdm-backend-blue ./universe-mdm-backend-blue -n universe-mdm
```

где:

- `universe-mdm-backend-blue` - название релиза приложения;
- `universe-mdm` - namespace, в котором будем разворачивать приложение;

#### Проверка

Проверим, что появились нужные абстракции в Kubernetes:

```sh
kubectl get all -n universe-mdm
```

А ещё можно посмотреть информацию о шаблонах и значениях переменных, которые отправил Helm (опционально):

```sh
helm get all -n universe-mdm universe-mdm-backend-blue
```

## Устновка компонента frontend-blue

Установка frontend возможна в одном варианте:

- SSL (HTTPS) - каталог `universe-mdm-frontend-SSL-blue`

Откройте для редактирования любым удобным текстовым редактором файл: `universe-mdm-frontend-SSL-blue/values.yaml`.

### Обязательные переменные для заполнения

- `replicaCount: 3` - количество реплик pod

- `repository: docker.universe-data.ru/unidata-ee/frontend - адрес приватного репозитория образов контейнеров;
- `tag: "release-6-11-df1431a6"` - укажите нужный тэг образа контейнера backend

> ### Важно
>
> Не забудьте отредактировать значение образа в `universe-mdm-frontend-SSL-blue/Chart.yaml` в строке `appVersion: "release-6-11-df1431a6"` во избежании путаницы в образах.

- `dockerconfigjson: []` - удалите символы `[]` и замените их на значение, которые вы получили в разделе [Создание secret для доступа в репозиторий контейнеров](#создание-secret-для-доступа-в-репозиторий-контейнеров). Пример заполнения:

```yaml
dockerconfigjson: eyJhdXRocyI6IHsiZG9ja2VyLnRlc3QucnUiOiB7InVzZXJuYW1lIjogImRvY2tlciIsICJwYXNzd29yZCI6ICJoVWlvNzY1NUdiZXRAT09wMDJtPT0ifX19
```

#### Переменные для HTTPS (SSL)

- `domain: cluster-k8s.ov.universe-data.ru` - заполните ваше действительное доменное имя;
- `crt:` - заполните значение `base64` `tls.crt` которое получили в разделе [Создание ключей SSL для доменных имён (SSL)](#создание-ключей-ssl-для-доменных-имён-ssl)
- `key:` - заполните значение `base64` `tls.key` которое получили в разделе [Создание ключей SSL для доменных имён (SSL)](#создание-ключей-ssl-для-доменных-имён-ssl)

И тоже самое для закомментированного блока Ingress, только для тестового доменного имени. (Указано в требованиях `blue-green.cluster-k8s.ov.universe-data.ru`)

### Установка

Прежде чем мы отправим чарт в кластер, надо убедиться, что чарт **валидный**. Для этого прогоним линтер:

```sh
helm lint ./universe-mdm-frontend-SSL-blue
```

При желании можем посмотреть, как выглядит манифест с подставленными переменными:

```sh
helm template ./universe-mdm-frontend-SSL-lint-blue
```

Установка

```sh
helm install universe-mdm-frontend-blue ./universe-mdm-frontend-SSL-blue -n universe-mdm
```

где:

- `universe-mdm-frontend-blue` - название релиза приложения;
- `universe-mdm` - namespace, в котором будем разворачивать приложение;

#### Проверка

Проверим, что появились нужные абстракции в Kubernetes:

```sh
kubectl get all -n universe-mdm
```

А ещё можно посмотреть информацию о шаблонах и значениях переменных, которые отправил Helm (опционально):

```sh
helm get all -n universe-mdm universe-mdm-frontend
```

#### Доступность MDM

Для `HTTPS`: `https://your-domain.local`

# Обновление

В данном случае будет показан пример обновления. Как только вы поймёте его принцип, то будет понятно, что такое обновление может иметь разные варианты, например, когда можно обновить только backend или только frontend.

По своей сути Green/Blue при обновлении могут меняться местами. Прежде всего необходимо проверить какой чарт сейчас установлен.

Выполним команду:

```sh
helm list -n universe-mdm
```

и посмотрим вывод:

```ini
❯ helm list -n universe-mdm
NAME                            NAMESPACE       REVISION        UPDATED                                 STATUS          CHART                                   APP VERSION
universe-mdm-backend-green      universe-mdm    1               2024-05-29 14:24:54.825913245 +0300 MSK deployed        universe-mdm-backend-green-0.2.0        release-6-11
universe-mdm-frontend-green     universe-mdm    3               2024-05-29 16:31:59.224134952 +0300 MSK deployed        universe-mdm-frontend-green-0.2.0       release-6-11-fcd40f4f

```

Из вывода очевидно, что у нас развернуты `green` поды, а значит обновления предстоит ставить на `blue` поды.

## Устанавливаем второй набор pod

В данном случае вторым набором pod будут под цветом blue

### Backend

Helm чарт компонента `backend` располагается в каталоге с названием`universe-mdm-backend-blue`.

Откройте для редактирования любым удобным текстовым редактором файл: `universe-mdm-backend-blue/values.yaml`.

Измените значение следующих переменных:

- `replicaCount: 3` - количество реплик pod

- `repository: docker.universe-data.ru/unidata-ee/backend` - адрес приватного репозитория образов контейнеров;

- `tag: "release-6-11-f8cef2ba"` - укажите нужный тэг образа контейнера backend

> ### Важно
>
> Не забудьте отредактировать значение образа в `universe-mdm-frontend-SSL-blue/Chart.yaml` в строке `appVersion: "release-6-11-df1431a6"` во избежании путаницы в образах.

- `dockerconfigjson: []` - удалите символы `[]` и замените их на значение, которые вы получили в разделе [Создание secret для доступа в репозиторий контейнеров](app://obsidian.md/index.html#%D1%81%D0%BE%D0%B7%D0%B4%D0%B0%D0%BD%D0%B8%D0%B5-secret-%D0%B4%D0%BB%D1%8F-%D0%B4%D0%BE%D1%81%D1%82%D1%83%D0%BF%D0%B0-%D0%B2-%D1%80%D0%B5%D0%BF%D0%BE%D0%B7%D0%B8%D1%82%D0%BE%D1%80%D0%B8%D0%B9-%D0%BA%D0%BE%D0%BD%D1%82%D0%B5%D0%B9%D0%BD%D0%B5%D1%80%D0%BE%D0%B2). Пример заполнения:

```yaml
dockerconfigjson: eyJhdXRocyI6IHsiZG9ja2VyLnRlc3QucnUiOiB7InVzZXJuYW1lIjogImRvY2tlciIsICJwYXNzd29yZCI6ICJoVWlvNzY1NUdiZXRAT09wMDJtPT0ifX19
```

- `postgres_address: "10.21.2.33:5432"` - адрес сервера PostgreSQL
- `postgres_username: "postgres"` - имя пользователя для авторизации на сервере PostgreSQL
- `postgres_password: "notpostgres"` - пароль пользователя на сервере PostgreSQL
- `database_name: "universe"` - имя базы данных.
- `search_cluster_address: "10.21.2.33:9200"` - адрес кластера Opensearch;
- `search_cluster_name: "docker-cluster"` - имя кластера Opensearch;

Подробную информацию по параметрам приложения см. в официальной [документации](https://doc.ru.universe-data.ru/6.10.0-EE/content/guides/install/index.html)

#### Установка

Прежде чем мы отправим чарт в кластер, надо убедиться, что чарт **валидный**. Для этого прогоним линтер:

```sh
helm lint ./universe-mdm-backend-blue
```

При желании можем посмотреть, как выглядит манифест с подставленными переменными:

```sh
helm template ./universe-mdm-backend-blue
```

Установка

```sh
helm install universe-mdm-backend-blue ./universe-mdm-backend-blue -n universe-mdm
```

где:

- `universe-mdm-backend-blue` - название релиза приложения;
- `universe-mdm` - namespace, в котором будем разворачивать приложение;

#### Проверка

Проверим, что появились нужные абстракции в Kubernetes:

```sh
kubectl get all -n universe-mdm
```

А ещё можно посмотреть информацию о шаблонах и значениях переменных, которые отправил Helm (опционально):

```sh
helm get all -n universe-mdm universe-mdm-backend-blue
```

> ### Перенаправление трафика будет производится на стороне frontend

### Frontend

Здесь также будем разворачивать Blue чарты для Frontend

Откройте для редактирования любым удобным текстовым редактором файл: `universe-mdm-frontend-SSL-blue/values.yaml`.

### Обязательные переменные для заполнения

- `replicaCount: 3` - количество реплик pod

- `repository: docker.universe-data.ru/unidata-ee/frontend - адрес приватного репозитория образов контейнеров;
- `tag: "release-6-11-df1431a6"` - укажите нужный тэг образа контейнера backend

> ### Важно
>
> Не забудьте отредактировать значение образа в `universe-mdm-frontend-SSL-blue/Chart.yaml` в строке `appVersion: "release-6-11-df1431a6"` во избежании путаницы в образах.

- `dockerconfigjson: []` - удалите символы `[]` и замените их на значение, которые вы получили в разделе [Создание secret для доступа в репозиторий контейнеров](#создание-secret-для-доступа-в-репозиторий-контейнеров). Пример заполнения:

```yaml
dockerconfigjson: eyJhdXRocyI6IHsiZG9ja2VyLnRlc3QucnUiOiB7InVzZXJuYW1lIjogImRvY2tlciIsICJwYXNzd29yZCI6ICJoVWlvNzY1NUdiZXRAT09wMDJtPT0ifX19
```

#### Переменные для HTTPS (SSL)

- `domain: cluster-k8s.ov.universe-data.ru` - заполните ваше действительное доменное имя;
- `crt:` - заполните значение `base64` `tls.crt` которое получили в разделе [Создание ключей SSL для доменных имён (SSL)](#создание-ключей-ssl-для-доменных-имён-ssl)
- `key:` - заполните значение `base64` `tls.key` которое получили в разделе [Создание ключей SSL для доменных имён (SSL)](#создание-ключей-ssl-для-доменных-имён-ssl)

И тоже самое для закомментированного блока Ingress, только для тестового доменного имени. (Указано в требованиях `blue-green.cluster-k8s.ov.universe-data.ru`)

#### Комментируем переменные для основного домена и настраваем frontend на тестовый домен

В файле: `universe-mdm-frontend-SSL-blue/values.yaml`. Есть две секции `Ingress`. Одна из них должна быть закомментирована. Пока развернём новый Frontend на тестовом домене. В этом случае Ingress должен выглядеть следующим образом:

```
# Production domain
#
# ingress:
#   domain: cluster-k8s.ov.universe-data.ru
#   crt: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUY1RENDQTh5Z0F3SUJBZ0lVQ...
#   key:S0tLS1CRUdJTiBQUklWQVRFIEtFWS0tLS0tCk1JSUpRZ0lCQURBTkJna3Foa2lHOXc...
#
# Test domain
#
ingress:
  domain: blue-green.cluster-k8s.ov.universe-data.ru
  crt: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUdFRENDQS9pZ0F3SUJBZ...
  key: LS0tLS1CRUdJTiBQUklWQVRFIEtFWS0tLS0tCk1JSUpRd0lCQURBTkJna3Foa2...

```

Можно заметить, что был закомментирован блок с тестовым доменом.

#### Направляем трафик на нужный backend

В `values.yaml` также проверьте секцию:

```yaml
backend:
  container_port: 8080
  forward_port: 9081
  # Здесь указываем на какой backend будем лить трафик
  color: blue
  #Don't change it
```

Значение `color: blue` означает, что ваш frontend будет направлять трафик на blue поды backend.

#### Установка

Прежде чем мы отправим чарт в кластер, надо убедиться, что чарт **валидный**. Для этого прогоним линтер:

```sh
helm lint ./universe-mdm-frontend-SSL-blue
```

При желании можем посмотреть, как выглядит манифест с подставленными переменными:

```sh
helm template ./universe-mdm-frontend-SSL-lint-blue
```

Установка

```sh
helm install universe-mdm-frontend-blue ./universe-mdm-frontend-SSL-blue -n universe-mdm
```

где:

- `universe-mdm-frontend-blue` - название релиза приложения;
- `universe-mdm` - namespace, в котором будем разворачивать приложение;

##### Проверка

Проверим, что появились нужные абстракции в Kubernetes:

```sh
kubectl get all -n universe-mdm
```

А ещё можно посмотреть информацию о шаблонах и значениях переменных, которые отправил Helm (опционально):

```sh
helm get all -n universe-mdm universe-mdm-frontend
```

#### Доступность MDM

В данном случае мы развернули blue frontend на тестовом домене, который смотрит на blue backend.
Для `HTTPS`: `<https://blue-green.cluster-k8s.ov.universe-data.ru>

Зайдём в UI и убедимся, в сведениях о системе, что установлены правильные образы.

### Переключение pod на основной домен

После того как мы убедились, что обновление работает. Можно переключить новый Frontend на основной домен.

Так как pod с новыми релизами у нас теперь под цветом `blue`, то и переключать мы будем на новые домены `blue` pod.

Для начала переключим старые `green` pods на тестовый домен, а новые `blue` переключим на основной.

#### Переключаем green pod на тестовый домен, а blue pod на основной

> # Важно
>
> Frontend может не заработать сразу и возможно придётся перезапустить podы. Однако это не повлияет на работу backend.

Откройте для редактирования любым удобным текстовым редактором файл: `universe-mdm-frontend-SSL-green/values.yaml`

И приводим блок `Ingress` к следующему виду:

```yaml
# Production domain
#
# ingress:
#   domain: cluster-k8s.ov.universe-data.ru
#   crt: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS...
#   key: LS0tLS1CRUdJTiBQUklWQVRFIEtFWS0tLS0tCk1JSUpRZ0...
#
# Test domain
#
ingress:
  domain: blue-green.cluster-k8s.ov.universe-data.ru
  crt: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUdFREND...
  key: LS0tLS1CRUdJTiBQUklWQVRFIEtFWS0tLS0tCk1JSUp...
```

Сохрание

Откройте для редактирования любым удобным текстовым редактором файл: `universe-mdm-frontend-SSL-blue/values.yaml`

И приводим блок `Ingress` к следующему виду:

```yaml
# Production domain
#
ingress:
  domain: cluster-k8s.ov.universe-data.ru
  crt: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUY...
  key: LS0tLS1CRUdJTiBQUklWQVRFIEtFWS0tLS0tCk1JSUpR...
#
# Test domain
#
# ingress:
#   domain: blue-green.cluster-k8s.ov.universe-data.ru
#   crt: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUdFRENDQS9p...
#   key: LS0tLS1CRUdJTiBQUklWQVRFIEtFWS0tLS0tCk1JSUpRd0lCQ...
```

Выполняем команду:

```sh
helm upgrade universe-mdm-frontend-green ./universe-mdm-frontend-SSL-green -n universe-mdm && helm upgrade universe-mdm-frontend-blue ./universe-mdm-frontend-SSL-blue -n universe-mdm && kubectl rollout restart deployment -n universe-mdm universe-mdm-frontend-blue && kubectl rollout restart deployment -n universe-mdm universe-mdm-frontend-green
```

> Замените `universe-mdm` на своё пространство имён, если это необходимо.

> К сожалению перезапуска pod frontend нельзя обойтись, однако frontend перезагружается достаточно быстро.

#### После обновления

Убедитесь, что в UI основного домена трафик перенаправляется на нужые pod.
Протестируйте обновление.

#### Если что-то пошло не так и нужно переключиться на старый релиз

Поменяйте блоки Ingress местами в `values.yaml` как описано выше и снова выполните команду, чтобы перенаправить трафик назад:

```sh
helm upgrade universe-mdm-frontend-green ./universe-mdm-frontend-SSL-green -n universe-mdm && helm upgrade universe-mdm-frontend-blue ./universe-mdm-frontend-SSL-blue -n universe-mdm && kubectl rollout restart deployment -n universe-mdm universe-mdm-frontend-blue && kubectl rollout restart deployment -n universe-mdm universe-mdm-frontend-green
```

# Дополнительные рекомендации к обнолению

## Как добавить новые переменные в Helm чарт

Основные переменные находятся в `values.yaml`, однако они являются ссылками на основные значения манифеста который находится по пути `templates/configmap.yaml`.

Допустим, как нередко бывает, нам необходимо добавить новую переменную в `backend`

### Порядок действий

Откройте для редактирования любым удобным текстовым редактором файл: `universe-mdm-backend-blue/values.yaml`.

Найдите секцию `config`. Она будет выглядеть так:

```yaml
config:
  guest_mode: "false"
  # Конфигурация для подключения к серверу PostgreSQL (Обязательно)
  postgres_address: "10.21.2.33:5432"
  postgres_username: "postgres"
  postgres_password: "notpostgres"
  database_name: "universe"
  ...
  ...
```

Добавляем какую-нибудь новую переменную в соответствии с YAML синтаксисом:

```yaml

config:
  guest_mode: "false"
  # Конфигурация для подключения к серверу PostgreSQL (Обязательно)
  postgres_address: "10.21.2.33:5432"
  postgres_username: "postgres"
  postgres_password: "notpostgres"
  database_name: "universe"
  ...
  ...
  new_variable: "value"
```

после чего добавим эту переменную в `templates/config-map-be.yaml`

и добавим её следующим образом:

```yaml
NEW_VARIABLE: "{{ .Values.config.new_variable }}"
```

Как видим, это просто ссылка на наш файл values.yaml

Сохраняем.

Прогоним линтер:

```sh
helm lint ./universe-mdm-backend-blue
```

При желании можем посмотреть, как выглядит манифест с подставленными переменными:

```sh
helm template ./universe-mdm-backend-blue
```

После чего выполняем helm upgrade

> ### Важная особенность
>
> Так как configmap не является частью основного манифеста, то pod не перезапустятся самостоятельно после деплоя. Для применения новой конфигурации pod надо перезагружать вручную.
> Не стоит беспокоится о простое. Pod можно перезагружать поочерёдно. На перезапускаемый pod трафик направляться не будет.
