---
sidebar_position: 7
slug: /rtsp
---

# RTSP Video Streams

With CloudPub you can publish RTSP video streams from surveillance cameras.

This allows you to access your cameras from the internet without opening ports on your router.

Additionally, you can view video streams in your personal account or the CloudPub application.

## RTSP Protocol

Video streams are published using the RTSP protocol.

This means you can use any RTSP player to access the video streams.

For example, in Windows 10 this can be done through VLC Media Player, in macOS - through QuickTime Player.

Simply open the player and enter the RTSP stream address provided by CloudPub.

### Graphical Interface Application

Select the publication type `Surveillance Camera (RTSP)` and enter the URL of your RTSP stream.

### Command Line

```bash
clo publish rtsp "[RTSP stream URL]"
```

After this, you will be provided with a URL where your RTSP video stream will be accessible.

```bash
Service published: rtsp://192.168.0.100:554/stream0 -> rtsp://rtsp.cloudpub.online:51243/stream0
```

The address specified after the arrow will be accessible from the internet.

You can view published streams in the "Video Streams" section of your personal account or application.
