---
sidebar_position: 5
slug: /webdav
---

# File Publishing

With CloudPub you can publish files and folders to share them with other users.

Additionally, this allows you to manage your files without uploading them to third-party services.

## WebDAV Protocol

Files are published using the WebDAV protocol.

This means you can use any WebDAV client to access the files.

For example, in Windows 10 this can be done through File Explorer, in macOS - through Finder.

Simply open File Explorer or Finder, enter the address provided by CloudPub, and enter your login and password.

After that, you will be able to work with files just like regular files on your computer.

### Graphical Interface Application

Select the publication type `File Folder (WebDAV)` and specify the path to the folder where the server will be installed.

### Command Line

```bash
clo publish webdav "[folder path]"
```

After this, you will be provided with a URL where your files will be accessible.

```bash
Service published: webdav://C:\Users\Administrator -> https://indelibly-fearless-jackdaw.cloudpub.local
```

The address specified after the arrow will be accessible from the internet.

To access files, you will need to enter a login and password. Your email is used as the login, and the password matches your account password.

You can manage files from the "File Manager" section in your personal account.

If you need to provide access to a file to other users, you can generate a download link for the file there.
