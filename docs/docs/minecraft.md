---
sidebar_position: 5
slug: /minecraft
---

# Сервер Minecraft

## Публикация сервера Minecraft в интернете

CloudPub позволяет публиковать сервера Minecraft в интернете, чтобы ваши друзья могли подключиться к нему из любой точки мира.

Если вы не используете моды, то это делается очень просто. Вам нужно указать путь к папке с сервером Minecraft, и CloudPub самостоятельно настроит все необходимые параметры.

### Приложение с графическим интерфейсом

Выберите тип публикации `minecraft` и укажите путь к папке, куда будет установлен сервер.

### Командная строка

```bash
clo publish minecraft [путь к папке с сервером]
```

После этого вам будет предоставлен URL, по которому ваш сервер будет доступен в интернете, например:

```bash
Сервис опубликован: minecraft://C:\Minecraft -> minecraft://minecraft.cloudpub.ru:32123
```

Указанный после стрелки (`-> minecraft://`) адрес и будет адресом, который и нужен игрокам для входа в игру.

В примере выше это `minecraft.cloudpub.ru:32123`


### Сервер с модами

Если вы используете сервер с модами, воспользуйтесь [инструкцией по публикации TCP сервиса](/docs/tcp).

Порт который нужно открыть для подключения к серверу Minecraft по умолчанию 25565, но может быть изменен в настройках сервера.

Более подробно это описано в [официальной документации Minecraft](https://minecraft.fandom.com/ru/wiki/%D0%A1%D0%BE%D0%B7%D0%B4%D0%B0%D0%BD%D0%B8%D0%B5_%D0%B8_%D0%BD%D0%B0%D1%81%D1%82%D1%80%D0%BE%D0%B9%D0%BA%D0%B0_%D1%81%D0%B5%D1%80%D0%B2%D0%B5%D1%80%D0%B0).