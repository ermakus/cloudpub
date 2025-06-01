---
sidebar_position: 100
slug: /changelog
---

# Version History

## 1.7.0 (May 29, 2025)

### New Features

 - Localization support
 - User action audit

### Bug Fixes

 - Regression when publishing UDP service

## 1.6.0 (May 8, 2025)

### New Features

 - Added `login` and `logout` commands for email and password authentication
 - Improved API interface for plugins

### Bug Fixes

 - Reconnection errors on connection loss
 - Incorrect display of some server errors
 - Publication error during long plugin loading
 - Incorrect client addresses for TCP connections
 - Error when reconnecting on connection loss
 - User gets logged out when logging in on another computer

## 1.5.198 (April 16, 2025)

### Bug Fixes

 - Regression when publishing RTSP
 - Form authentication regression
 - Ping measurement error with small latency
 - Minecraft server installs in wrong location
 - Error displaying URL for 1C

## 1.5.190 (April 9, 2025)

### New Features

 - Application installation as a service

### Bug Fixes

 - Phone number not saved
 - Incorrect status display when re-adding the same publication

## 1.5.171 (April 8, 2025)

### New Features

 - Ability to edit HTTP request headers
 - Request inspector: Gzip and deflate decoding
 - Request inspector: Preview for images, HTML, JSON, XML
 - New command: `clo ping`
 - Header now contains external publication address (like regular reverse proxy)

## 1.4.102 (April 5, 2025)

### Bug Fixes

 - Windows error: "Either the application has not called WSAStartup, or WSAStartup failed"

## 1.4.79 (February 20, 2025)

### Bug Fixes

 - Team invitation accepted if mail service tries to load link
 - Periodic agent restart under heavy channel load

## 1.4.86 (March 4, 2025)

### New Features

 - New parameter `minecraft_java_opts` for specifying JVM parameters

## 1.4.79 (February 20, 2025)

### Bug Fixes

 - WebDAV publication error if old vcredist version is installed
 - Host header now contains port (if different from default port)
 - Fixed local URL display

## 1.4.76 (February 14, 2025)

### New Features

 - Current version display in interface

### Bug Fixes

 - Filter not working on invitations page
 - Cannot add domain consisting only of digits
 - No signature for executable files on Windows

## 1.4.52 (February 6, 2025)

### Bug Fixes

 - Interface error when configuring access parameters for new publication
 - Address converts to IP when adding new publication

## 1.4.41 (January 30, 2025)

### New Features

 - RTSP protocol support
 - RTSP stream player in personal account

## 1.3.115 (January 23, 2025)

### New Features

 - Command line utilities for macOS are now signed and notarized

## 1.3.63 (January 18, 2025)

### Bug Fixes

 - 32-bit version client doesn't connect to server
 - Settings save error

## 1.3.33 (January 10, 2025)

### New Features

 - TCP connection display in traffic inspector
 - Size display in traffic inspector

## 1.3.63 (January 18, 2025)

### New Features

 - Load balancer IP address changed due to migration to wider channel
 - Added domain delegation status display

### Bug Fixes

 - Email is case-sensitive during authentication
 - 1C publication path selection button doesn't work properly

## 1.3.1 (December 17, 2024)

### New Features

 - HTML form authentication support for services
 - New Linux architectures: ARMV5TE, AARCH64

## 1.2.115 (December 8, 2024)

### New Features

 - Added request geolocation in traffic inspector
 - Can now specify local jar file for Minecraft server
 - Updated dependencies
 - Updated documentation
 - Cosmetic interface changes

## 1.2.104 (December 5, 2024)

### New Features

 - Added client network error tracking on server side
 - New option: `unsafe_tls` for ignoring certificate errors

## 1.2.102 (December 4, 2024)

### New Features

 - User invitations to team
 - Basic authentication support for services
 - WebDAV access rights support

## 1.2.66 (November 24, 2024)

### New Features

 - Support for custom 2nd and 3rd level domains
 - Automatic Let's Encrypt certificates for custom domains

## 1.2.28 (November 22, 2024)

### New Features

 - New parameter `1c_publish_dir` - path where 1C publication files will be created

## 1.2.21 (November 20, 2024)

### New Features

 - Minecraft server updated to version 1.21.3
 - New config parameter `minecraft_server` for specifying URL to Minecraft server jar file

## 1.2.19 (November 15, 2024)

### New Features

 - More detailed error traces in client log

### Bug Fixes

 - Error when deleting WebDAV file from personal account

## 1.2.15 (November 10, 2024)

### New Features

 - Graphical interface application now includes all personal account functions
 - Minecraft server console is displayed when starting
 - Docker image configuration via environment variables
 - When connecting a new agent with the same ID, the old agent is automatically disconnected

### Bug Fixes

 - Incorrect error display
 - Client crash in rare cases when loading external modules

## 1.1.56 (November 6, 2024)

### New Features

 - clo register command for registering publication without starting process

### Bug Fixes

 - Error when changing subdomain in admin panel

## 1.1.50 (October 31, 2024)

### New Features

 - Published Docker image

### Bug Fixes

 - 400 error during authentication
 - default.vrd file overwritten on republication

## 1.1.47 (October 26, 2024)

### New Features

 - Added ability to publish files via WebDAV protocol
 - Added file manager to personal account

## 1.1.21 (October 20, 2024)

### New Features

 - Can analyze HTTP response body
 - Accelerated GUI application interface
 - Added ability to filter all tables
 - Ability to copy or export HTTP request and response
 - Binary data display in HTTP traffic

### Bug Fixes

 - No status line in server response
 - Line break in saved request body doesn't match convention

## 1.1.10 (October 17, 2024)

### New Features

 - HTTP request display in personal account
 - Profile management
 - New version notifications
 - Agent version and platform display
 - Improved user interface

### Bug Fixes

 - Added missing X-Forwarded-* headers

## 1.0.108 (October 6, 2024)

### New Features

 - New protocol: minecraft
 - Automatic Minecraft server installation and configuration
 - More convenient publication link display

## 1.0.96 (October 4, 2024)

### New Features

 - Added traffic display for each publication
 - Updated documentation

### Bug Fixes

 - Error in graphical interface when deleting all records from table
 - No API key message when running `cli publish` command

## 1.0.94 (October 3, 2024)

### New Features

 - Command line parameter support for GUI application

## 1.0.72 (October 1, 2014)

### New Features

 - Added graphical interface applications
 - New command line parameters
 - Support for publishing 1C databases on Linux

## 1.0.0 (September 20, 2014)

### New Features

 - Basic functionality
 - Command line utilities
