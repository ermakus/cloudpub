---
sidebar_position: 98
description: Using CloudPub with Docker
slug: /docker
---

# Docker Image

## Using CloudPub with Docker

You can use the ready-made [Docker image](https://hub.docker.com/repository/docker/cloudpub/cloudpub/general) for the CloudPub agent.

Example command to run a tunnel to port 8080 on the host machine looks like this:

```bash
docker run --net=host -it -e TOKEN=xyz cloudpub/cloudpub:latest publish http 8080
```

:::tip
The Docker version uses the same command line parameters as the regular version.
:::

For macOS or Windows users, the `--net=host` option will not work.

You will need to use the special URL host.docker.internal, as described in the Docker [documentation](https://docs.docker.com/desktop/mac/networking/#use-cases-and-workarounds).

```bash
docker run --net=host -it -e TOKEN=xyz cloudpub/cloudpub:latest \
       publish http host.docker.internal:8080
```

## Preserving Settings on Container Restart

When starting a container, CloudPub creates a new agent and a new unique URL for tunnel access.

To preserve settings on container restart, you should create a volume for storing configuration and cache:

```bash
docker volume create cloudpub-config
```

Then, when starting the container, you should use this volume:

```bash
docker run -v cloudpub-config:/home/cloudpub --net=host -it -e TOKEN=xyz \
              cloudpub/cloudpub:latest publish http 8080
```

In this case, all agent settings will be saved in the `cloudpub-config` volume and will be available on the next container start.

## Publishing Multiple Resources at Once

You can specify multiple resources for publication in environment variables, separating them with commas:

```bash
docker run -v cloudpub-config:/home/cloudpub --net=host -it\
              -e TOKEN=xyz \
              -e HTTP=8080,8081 \
              -e HTTPS=192.168.1.1:80 \
              cloudpub/cloudpub:latest run
```

The environment variable name matches the protocol name. The following protocols are available:

 * HTTP
 * HTTPS
 * TCP
 * UDP
 * WEBDAV
 * MINECRAFT

## Version for ARM Processors

For ARM processors, the image `cloudpub/cloudpub:latest-arm64` is available
