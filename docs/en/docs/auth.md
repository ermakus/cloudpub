---
sidebar_position: 15
slug: /auth
---

# Authentication and Access Control

## Authentication Types

CloudPub supports two types of authentication:

### Basic Auth

Basic Auth is a standard HTTP authentication method (RFC 7617) that:

- Is supported by all protocols
- Allows connection through both browser and other clients
- Is ideal for WebDAV, allowing mounting as a network drive
- Requires credentials to be transmitted with each request

### Form Auth

Form Auth is authentication through an HTML form that:

- Is supported by HTTP, HTTPS, and 1C protocols
- Is designed for access through web browser
- Can be used with WebDAV, but then access will only be possible through browser
- Is more convenient for end users

## Authentication Support by Protocol

| Protocol | Basic Auth | Form Auth |
|----------|------------|-----------|
| HTTP     | ✓          | ✓         |
| HTTPS    | ✓          | ✓         |
| WebDAV   | ✓          | ✓*        |
| 1C       | ✓          | ✓         |
| TCP      | ✓          | ✗         |
| UDP      | ✓          | ✗         |

\* WebDAV with Form Auth is only accessible through browser

## Access Control (ACL)

For each published resource, you can configure access rules by specifying:

- User email
- User role

### User Roles

| Role | Description |
|------|-------------|
| admin | Full access to resource |
| reader | Read-only access |
| writer | Read and write access (only for WebDAV) |

### Rule Configuration

Access rules are set when publishing a resource through the `--acl` parameter in the format `email:role`.
You can specify multiple rules for different users.

Example:
```bash
clo publish --acl user@example.com:reader --acl admin@example.com:admin http 8080
```
