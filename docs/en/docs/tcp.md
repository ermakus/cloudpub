---
sidebar_position: 3
slug: /tcp
---

# TCP and UDP Services

## Publishing TCP Services

Publishing a service running on TCP protocol is done similarly to publishing an HTTP service, but with specifying the TCP protocol:

```bash
clo publish tcp 22
```

In this example, we are publishing a service running on port 22 (SSH).

Unlike HTTP services, TCP services do not get a unique domain name and are only available at the address `tcp.cloudpub.online` with a unique port.

Just like with HTTP services, you can specify the address of any host in the local network:

```bash
clo publish tcp myserver:3389
```

In this example, we are publishing a service running on port 3389 (RDP) on host `myserver`.

## Publishing UDP Services

Publishing a service running on UDP protocol is done similarly to publishing a TCP service, but with specifying the UDP protocol:

```bash
clo publish udp 53
```

In this example, we are publishing a service running on port 53 (DNS).
