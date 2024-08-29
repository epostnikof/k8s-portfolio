# Для чего этот Dockerfile?

Данный Dockerfile собирает образ для CI/CD Helm чартов.

# Cборка

- Собираем образ:

```sh
 docker build -t k8s-ci:1.0 .

```

- Даём ему тег для приватного репозитория:

```sh
docker tag k8s-ci:1.0 docker.universe-data.ru/smart-etl/k8s-ci:1.0
```

- Пушим (не забудьте авторизоваться на приватном репозитории):

```sh
docker push k8s-ci:1.0 docker.universe-data.ru/smart-etl/k8s-ci:1.0

```
