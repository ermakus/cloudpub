---
sidebar_position: 6
slug: /minecraft
---

# Minecraft Server

## Publishing Minecraft Server on the Internet

CloudPub allows you to publish Minecraft servers on the internet so your friends can connect to it from anywhere in the world.

If you're not using mods, this is very simple. You need to specify the path to the Minecraft server folder, and CloudPub will automatically configure all necessary parameters.

### Graphical Interface Application

Select the publication type `minecraft` and specify the path to the folder where the server will be installed.

### Command Line

```bash
clo publish minecraft [path to server folder]
```

After this, you will be provided with a URL where your server will be accessible on the internet, for example:

```bash
Service published: minecraft://C:\Minecraft -> minecraft://minecraft.cloudpub.online:32123
```

The address specified after the arrow (`-> minecraft://`) is the address that players need to enter the game.

In the example above, this is `minecraft.cloudpub.online:32123`

### Server with Mods

If you're using a server with mods, use the [TCP service publication instructions](/docs/tcp).

The port that needs to be opened for connecting to the Minecraft server is 25565 by default, but can be changed in the server settings.

This is described in more detail in the [official Minecraft documentation](https://minecraft.fandom.com/wiki/Tutorials/Setting_up_a_server).
