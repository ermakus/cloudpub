---
sidebar_position: 1
slug: /
---

import { Downloads, getUrl, getFile } from 'src/components/dashboard/downloads';
import CodeBlock from '@theme/CodeBlock';

# Быстрый старт

Как начать использовать **CloudPub за 5 минут**.

## Установите клиент

<Downloads />

## Приложение с графическим интерфейсом

 - Создайте аккаунт в [личном кабинете](https://cloudpub.ru/dashboard)
 - Запустите приложение (исполнимый файл называется `cloudpub`)
 - Авторизуйтесь:

![Авторизация](/img/login-form.png)

 - Нажмите на кнопку `Новая публикация`
 - Выберите тип ресурса, который вы хотите опубликовать
 - Введите необходимые данные:

![Публикация](/img/publication.png)

 - Нажмите на кнопку `Опубликовать`
 - После этого вам будет предоставлен URL, по которому ресурс будет доступен в интернете

## Утилита для командной строки

### Windows {#windows}

 - Скачайте архив: <a href={getUrl('windows', 'x86_64')}>{getFile('windows', 'x86_64')}</a>
 - Распакуйте архив в любую папку. Для удобства рекомендуем распаковать архив в папку `C:\Windows\System32`
 - Нажмите `Win + R`
 - Введите `cmd.exe` и нажмите `Enter`
 - В открывшемся окне введите `cd <путь к папке>` и нажмите `Enter`<sup>*</sup>

 <sup>*</sup> Этот пункт не обязателен, если вы распаковали архив в папку `C:\Windows\System32`

### Linux {#linux}

 - Откройте терминал
 - Скачайте архив при помощи команды

<CodeBlock>wget {getUrl('linux', 'x86_64')}</CodeBlock>

 - Распакуйте архив при помощи команды

<CodeBlock>tar -xvf {getFile('linux', 'x86_64')}</CodeBlock>

### MacOS {#macos}

 - Откройте терминал
 - Скачайте и распакуйте архив для вашей архитектуры:

#### Apple Silicon:

<CodeBlock>curl {getUrl('macos', 'aarch64')} -o {getFile('macos', 'aarch64')}
tar -xvf {getFile('macos', 'aarch64')}</CodeBlock>

#### Intel:

<CodeBlock>curl {getUrl('macos', 'x86_64')} -o {getFile('macos', 'x86_64')}
tar -xvf {getFile('macos', 'x86_64')}</CodeBlock>


## Привяжите ваш аккаунт

Если в еще этого не сделали, создайте аккаунт на в [личном кабинете](https://cloudpub.ru/dashboard). После этого привяжите ваш аккаунт к клиенту, выполнив следующую команду:

```bash
clo set token <ваш токен>
```

Свой токен вы можете найти на главной странице в личном кабинете после регистрации.

## Опубликуйте ваш первый ресурс

Для публикации локального HTTP сервера работающего на порте 8080 выполните команду:

```bash
clo publish http 8080
```

После этого вам будет предоставлен URL, по которому ваш ресурс будет доступен в интернете, например:

```bash
Service published: http://localhost:8080 -> https://wildly-suitable-fish.cloudpub.ru
```

В этом случае ваш ресурс будет доступен по адресу `https://wildly-suitable-fish.cloudpub.ru`.

URL вашего ресурса будет отличаться от приведенного в примере.
