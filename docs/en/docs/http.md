---
sidebar_position: 2
slug: /http
---

# HTTP and HTTPS Services

## Publishing HTTP Services

To publish a local HTTP server running on a local interface, simply execute the command:

```bash
clo publish http 8080
```

where 8080 is the port on which your server is running.

After executing the command, you will receive a message that your service has been published:

```bash
Service published: http://localhost:8080 -> https://wildly-suitable-fish.cloudpub.online
```

The service will be publicly available via HTTPS protocol, and we will automatically generate a certificate for this domain.

If you need to publish a service running on another host in the local network, you can specify the IP address or host when publishing:

```bash
clo publish http 192.168.1.1:80
```

In this case, the service will be published on the specified IP address and port (in this example, it could be your router's admin panel)

## Publishing HTTPS Services

Publishing HTTPS services is similar to publishing HTTP services, but with specifying the HTTPS protocol:

```bash
clo publish https 443
```

## HTTP and HTTPS Request Headers

When publishing HTTP and HTTPS services, you can override or specify additional headers that will be added to requests sent to your local server.

This can be useful if your server requires certain headers to work, for example, a `Host` header matching the local server address (`localhost`)

```bash
clo publish -H Host:localhost https 443
```
