---
sidebar_position: 1
slug: /
---

# Быстрый старт

Как начать использовать **CloudPub за 5 минут**.

## Cкачайте клиент для вашей операционной системы

- [Windows](https://cloudpub.ru/download/windows/x86_64/cloudpub-client.exe)
- [Linux](https://cloudpub.ru/download/linux/x86_64/cloudpub-client)
- [MacOS (Intel)](https://cloudpub.ru/download/mac/x86_64/cloudpub-client)
- [MacOS (ARM)](https://cloudpub.ru/download/mac/arm/cloudpub-client)

### Для Linux и MacOS дайте файлу права на выполнение

```bash
chmod +x cloudpub-client
```


## Привяжите ваш аккаунт

Если в еще этого не сделали, создайте аккаунт на [cloudpub.ru](https://cloudpub.ru/dashboard). После этого привяжите ваш аккаунт к клиенту, выполнив следующую команду:

```bash
./cloudpub-client set token <ваш токен>
```

Свой токен вы можете найти на главной странице в личном кабинете после регистрации.

## Опубликуйте ваш первый ресурс

Для публикации локального HTTP сервера работающего на порте 8080 выполните команду:

```bash
./cloudpub-client publish http 8080
```

После этого вам будет предоставлен URL, по которому ваш ресурс будет доступен в интернете, например:

```bash
Service published: http://localhost:8080 -> https://wildly-suitable-fish.cloudpub.ru
```

В этом случае ваш ресурс будет доступен по адресу `https://wildly-suitable-fish.cloudpub.ru`.

URL вашего ресурса будет отличаться от приведенного в примере.
