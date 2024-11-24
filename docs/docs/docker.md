---
sidebar_position: 8
description: Использование CloudPub с Docker
slug: /docker
---

# Образ Docker

## Использование CloudPub с Docker

Вы можете использовать готовый образ Docker для агента CloudPub.

Пример команды для запуска туннеля на порт 8080 на хост-машине выглядит следующим образом:

```bash
docker run --net=host -it -e TOKEN=xyz cloudpub/cloudpub:latest publish http 8080
```

:::tip
Docker-версия использует те же параметры командной строки, что и обычная версия.
:::

Для пользователей MacOS или Windows, опция `--net=host` не будет работать.

Вам нужно будет использовать специальный URL host.docker.internal, как описано в [документации](https://docs.docker.com/desktop/mac/networking/#use-cases-and-workarounds) Docker.

```bash
docker run --net=host -it -e TOKEN=xyz cloudpub/cloudpub:latest host.docker.internal:8080
```

## Сохранение настроек при перезапуске контейнера

При запуске контейнера, CloudPub создает новый агент и новый уникальный URL для доступа к туннелю.

Что бы сохранить настройки при перезапуске контейнера, следует создать том для хранения данных (конфигурации и кеша):


```bash
docker volume create cloudpub-config
```

Затем, при запуске контейнера, следует использовать этот том:

```bash
docker run -v cloudpub-config:/home/cloudpub --net=host -it -e TOKEN=xyz \
              cloudpub/cloudpub:latest publish http 8080
```

В этом случае все настройки агента будут сохранены в томе `cloudpub-config` и будут доступны при следующем запуске контейнера.

## Публикация сразу нескольких ресурсов

Вы можете указать несколько ресурсов для публикации в переменных окружения, разделяя их запятыми:

```bash
docker run -v cloudpub-config:/home/cloudpub --net=host -it\
              -e TOKEN=xyz \
              -e HTTP=8080,8081 \
              -e HTTPS=192.168.1.1:80 \
              cloudpub/cloudpub:latest run
```

Названия переменной окружения совпадает с названием протокола. Доступны следующие протоколы:

 * HTTP
 * HTTPS
 * TCP
 * UDP
 * WEBDAV
 * MINECRAFT

## Версия для ARM процессоров

Для ARM процессоров доступен образ `cloudpub/cloudpub:latest-arm64` (`--platform linux/arm64`).
