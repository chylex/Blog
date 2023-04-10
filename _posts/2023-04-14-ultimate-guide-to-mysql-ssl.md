---
title: "The Ultimate Guide to Securing MySQL / MariaDB + PHP with SSL"
subtitle: "%pub"
date: 2023-04-14
commentid: 4
---

By default, all communication between a MySQL or MariaDB server and its clients is unencrypted. That's fine if both the database server and client are on the same machine, or connected by a network you fully control, but as soon as anything touches the internet — or even an internal data center network the [NSA may have secretly tapped into](https://www.washingtonpost.com/world/national-security/nsa-infiltrates-links-to-yahoo-google-data-centers-worldwide-snowden-documents-say/2013/10/30/e51d661e-4166-11e3-8b74-d89d714ca4dd_story.html) — all bets are off, and you need SSL to ensure that the communication cannot be spied on or tampered with. This post will guide you through the entire process in an abundance of detail.

To be clear, I'm no expert on cryptography, and I certainly wasn't expecting to be writing a whole tutorial on setting up SSL for MySQL / MariaDB + PHP within hours of getting mine to work, but while researching this I found so much outdated or just straight up bad information that I took time to dig deep into every step of the process. While reading this guide, you should never feel you're being told to run a command or change some code without an explanation that justifies it.

# 0. Prerequisites

I will assume that you have a MySQL or MariaDB server, access to its configuration files, and PHP scripts that connect to it. I will also assume you are always using the most recent version of all software involved. I cannot predict any future software updates that invalidate something in this post, so if you run into issues, please let me know in the comments.

Many parts of this guide are based on the official documentation of [MySQL](https://dev.mysql.com/doc/refman/8.0/en/creating-ssl-files-using-openssl.html) and [MariaDB](https://mariadb.com/kb/en/certificate-creation-with-openssl/).

Now, get yourself a Linux machine with `openssl` and let's get started.

# 1. Generating Certificates

Let's establish some terminology. SSL uses "asymmetric cryptography" to establish a secure communication channel. Every *entity* needs a key pair — a private key, and a public key — that each serve two functions:
1. The public key is used to encrypt messages. Only the private key can decrypt those messages.
2. The private key is used to sign messages. The public key can verify those signatures.

The public key will be embedded in a *public key certificate*, which contains additional information about the identity of its owner. The private key and public key certificate will be generated using ~~magic~~ a bunch of math, and stored in separate files.

From now on, I will simplify the terminology and use "key" to mean the private key, and "certificate" or "cert" to mean the public key certificate. Later we will see this simplified terminology used in both MySQL / MariaDB configuration, and in the PHP code for configuring the database connection.

Before generating any keys of certificates, we must pick an *algorithm*. Both official documentations use 2048-bit RSA. As far as RSA goes, 2048 bits is the absolute minimum nowadays. It might be a good idea to increase the key size to 3072, 4096, or even more bits for better resilience against progress in (non-quantum) computing performance, but that comes at the expense of spending more time establishing every connection. The world seems to be moving away from RSA and towards elliptic curves, which have several benefits including much smaller keys, so we might as well use the current best thing. Based on recommendations from [Trail of Bits](https://blog.trailofbits.com/2019/07/08/fuck-rsa/) and [Soatok](https://soatok.blog/2022/05/19/guidance-for-choosing-an-elliptic-curve-signature-algorithm-in-2022/), I will use Ed25519.

## Certificate Authority

First, we roleplay as a "Certificate Authority" (CA), the first *entity* for which we will be generating a key and a certificate. If you hate fun, you can take inspiration from modern "Free-to-play" games and simply pay a *real* Certificate Authority to skip this part.

The purpose of the CA is to *sign other certificates*, using the (private) CA key. We will then distribute the (public) CA certificate to every computer that either hosts the database server or connects to it. When these *other certificates* are sent and received over an untrusted network, the CA certificate will verify their signature. If the signature is valid, we know that it must have been signed by our CA — which we trust — so the *other certificate* can also be trusted. If the signature is not valid, it means the *other certificate* has been forged or otherwise corrupted, and it is impossible to establish secure and trusted communication with the database server.

It's terminal time. Navigate to a folder where you want your certificates.

This snippet generates a private key using the Ed25519 algorithm, and saves it to a `ca_key.pem` file.
```bash
openssl genpkey -algorithm ed25519 > ca_key.pem
```

Now, we use the private key to generate a public key certificate, and save it to `ca_cert.pem`. The following snippet includes some things you should change, so read on before you copy/paste it into a terminal.
```bash
openssl req -new -x509 -nodes -days 365000 -subj "/C=US/O=organization/OU=organizational_unit/CN=common_name" -key ca_key.pem -out ca_cert.pem
```

Let's go through what this means:
1. `openssl req -new` means we are creating a new "certificate signing request".
2. `-x509` means that the "certificate signing request" will be immediately turned into a self-signed certificate in the X.509 format. Otherwise, it would be saved as a file, and we'd need another command to sign it.
3. `-nodes` ("no DES") disables encryption of the certificate. If encryption is enabled, you will be asked for a passphrase, and then must provide this passphrase whenever you want to use the certificate. Encrypting certificates provides more security at the expense of convenience, but I cannot find any evidence that either MySQL or MariaDB supports encrypted certificates, so we don't have a choice here.
4. `-days 365000` sets the expiry time to roughly 1000 years, which is fairly optimistic considering how humanity is going. You can use shorter expiry times, but you need to think about renewal and this s\*\*t is already complicated enough. Shorter expiry times can help if your private key leaks and you never realize, but recommended expiry times are often in the realm of months or years, which is plenty of time for an attacker to cause harm. Moreover, if you do realize your private key leaked, you can regenerate all keys and certificates and swap them out, which should be relatively easy since they only reside on computers you fully control.
5. `-subj ...` is the spicy stuff. It is a slash-delimited sequence of key-value pairs of various fields embedded in the certificate. Most are optional, but useful for documenting where the certificate came from. There are standards for these, but since you are the only one using these certificates, for the unimportant fields just type in whatever doesn't crash `openssl`.
   - `C` is a two-letter country code. The lesser-known your country is, the more I recommend setting it.
   - `O` is the organization name. Despite my lack of organization, I set it to my nickname.
   - `OU` is the organizational unit. I set it to `mysql` to describe where these certificates will be used.
   - `CN` is the common name, which is supposed to identify the certificate's origin. For the CA, it's not really important. For example, you can just set it to your username. I set it to the domain name of the server which stores the CA key and certificate, but if you are planning to do that, you must use a different domain name than the one used for the database server — we will come back to that later.
   - There are many more possible fields, but you really don't need more than this.
   - In both official documentations, these fields (and more) are set interactively as part of running this command. The `-subj` argument automates setting these fields, so you can throw this into a non-interactive script file.
6. `-key` is the file name of the private key.
7. `-out` is the file name to create for the certificate.

We end up with a private key `ca_key.pem` that we need to keep secret, and a public key certificate `ca_cert.pem` that needs to be copied to the database server and to every client that connects to the database server.

## Server Certificates

Let's now generate a key and a certificate for the database server. When a client connects to the database server, the server will automatically send its certificate to the client. After the client verifies that the server certificate was signed by the CA certificate, it will use the server certificate to encrypt some secret information which only the server can decrypt. This secret information is used to establish a new, symmetrically encrypted communication channel. You might be asking why we are establishing a new encrypted channel when we already have one, and there are two reasons:
1. The client may not have its own key and certificate, in which case the server has no way to encrypt messages in a way that only the client can decrypt.
2. Asymmetric encryption needs a lot more computing resources than symmetric encryption.

Now that we've finished our educational side-quest, let's generate a key and a *certificate signing request*.
```bash
openssl req -newkey ed25519 -nodes -subj "/C=US/O=organization/OU=organizational_unit/CN=server_hostname" -keyout "server_key.pem" -out "server_req.pem"
```

Most of these are the same as before. The differences are:
1. `-newkey` is like `-new`, but it also generates a private key at the same time as the certificate signing request. Note that this time there is no `-x509`, so we do actually create a certificate signing request that we will sign later.
2. `ed25519` uses the Ed25519 algorithm for the private key.
3. `-subj ...` is largely the same, **but!**
   - `CN` must be the hostname of the database server you use in your PHP script! If it doesn't match, the connection will fail with an error:
     ```
     Peer certificate CN=`...' did not match expected CN=`...'
     ```
     It must also be different from the `CN` field you used for the Certificate Authority, otherwise database servers with OpenSSL will reject the connection with this error:
     ```
     OpenSSL Error messages: error:1416F086:SSL routines:tls_process_server_certificate:certificate verify failed
     ```
     Inconveniently, MariaDB documentation does not mention this at all, and MySQL documentation does but too early — before you learn what any of this even means.
4. `-keyout` is the file name to create for the private key.

At this point, both official documentations say to run a command to "remove the passphrase" from the private key. If you remember from earlier, the `-nodes` argument — which both documentations use — already disables passphrase-based encryption, so there is no point removing something that doesn't exist.

Let's turn the certificate signing request into an actual certificate by using our Certificate Authority to sign it:
```bash
openssl x509 -req -days 365000 -set_serial 1 -CA ca_cert.pem -CAkey ca_key.pem -in "server_req.pem" -out "server_cert.pem" -extfile /etc/ssl/openssl.cnf -extensions usr_cert
```

New thingies to learn!
1. `openssl x509` begins a command related to X.509 certificates. You may be wondering — we already did a bunch of things with X.509 certificates, why have we not seen this command yet? Anyway,
2. `-req` means we are turning a certificate signing request into a certificate. Very different from `req`.
3. `-set_serial` specifies a serial number for the certificate. This number should be **unique for our CA**. This server certificate uses serial number `1`, the next certificate we make with the same CA will use serial number `2`, etc.
4. `-CA` is a path to the CA certificate.
5. `-CAkey` is a path to the CA key, and also the fourth f\*\*\*ing way to capitalize arguments in the `openssl` command.
6. `-in` is the file name of the certificate signing request.
7. `-extfile` is a path to a file containing X.509 v3 extensions. We use the default OpenSSL configuration file.
8. `-extensions usr_cert` then uses a particular set of X.509 v3 extensions that the default configuration file uses for non-CA certificates.

The last two arguments, `-extfile` and `-extensions`, are what's needed to generate a version 3 certificate. Omitting them would generate a version 1 certificate, which works fine if your database server and client use OpenSSL, but may not work with a different SSL library.

At the time of writing, both official documentations only show how to generate version 1 certificates; [MariaDB documentation](https://mariadb.com/kb/en/certificate-creation-with-openssl/) does explain the problem with version 1 certificates, promises to update the documentation soon, and then links to an unresolved [2-year-old issue](https://jira.mariadb.org/browse/MDEV-25701) about updating the documentation.

Finally, this command just removes the certificate signing request.
```bash
rm "server_req.pem"
```

## Client Certificates

Client certificates are optional. We could not use them at all, or use the same key and certificate everywhere, or generate a new key and certificate for each client (PHP application).

The process for generating a client key and certificate is the same as for the server, we just need to change a few parts:
1. In file names, substitute `server_` for `client_` or `client_1_` or whatever else makes sense to you.
2. Increase the serial number. The server certificate used `1`, so the first client certificate will use `2`.
3. While you technically don't need to use a different `CN` than the one in the server certificate — as in, it will not throw errors — if someone steals your client key, they will be able to impersonate your database server by using the client key and certificate in place of the server key and certificate. By changing the `CN` to something different from your server hostname, attempting to impersonate your database server would fail, because as explained earlier, the clients check that the server certificate's `CN` field matches the server hostname.

Here, have a convenient snippet with all three commands. Don't forget to change the `-subj`.
```bash
openssl req -newkey ed25519 -nodes -subj "/C=US/O=organization/OU=organizational_unit/CN=client_name" -keyout "client_key.pem" -out "client_req.pem"

openssl x509 -req -days 365000 -set_serial 2 -CA ca_cert.pem -CAkey ca_key.pem -in "client_req.pem" -out "client_cert.pem" -extfile /etc/ssl/openssl.cnf -extensions usr_cert

rm "client_req.pem"
```

## Verify Certificates

This command will verify that one or more certificates have been signed by the CA. The `-CAfile` argument is the same as `-CA` in the previous commands, because Big Documentation needs you to never remember how commands work. Every argument after that is a path to a certificate file that we want to verify.
```bash
openssl verify -CAfile ca_cert.pem server_cert.pem client_cert.pem
```

We can also look at the certificate data, such as the fields from `-subj` or the expiry date 1000 years in the future. The `-noout` argument prevents outputting the actual certificate itself.
```bash
openssl x509 -text -noout -in ca_cert.pem
openssl x509 -text -noout -in server_cert.pem
openssl x509 -text -noout -in client_cert.pem
```

At this point, you should have files containing the key and certificate for the CA, server, and any number of clients you desire.
```
ca_cert.pem
ca_key.pem
client_cert.pem
client_key.pem
server_cert.pem
server_key.pem
```

If you do, hooray! Make sure the files have the correct ownership and mode, pat yourself on the back, and get ready to drop into the next circle of hell.

# 2. Server Configuration

Here, the official documentation seems to be spot on for both [MySQL](https://dev.mysql.com/doc/refman/8.0/en/using-encrypted-connections.html) and [MariaDB](https://mariadb.com/kb/en/securing-connections-for-client-and-server/).

The quick rundown is, locate your MySQL or MariaDB configuration files, find or create a `[mysqld]` or `[mariadb]` section in them, and set `ssl_ca`, `ssl_cert`, and `ssl_key` to paths to the correct files. For these examples, pretend I copied the 3 required files into the `/certs` folder.

### MySQL

```ini
[mysqld]
ssl_ca   = /certs/ca_cert.pem
ssl_cert = /certs/server_cert.pem
ssl_key  = /certs/server_key.pem
```

### MariaDB

```ini
[mariadb]
ssl_ca   = /certs/ca_cert.pem
ssl_cert = /certs/server_cert.pem
ssl_key  = /certs/server_key.pem
```

## Restart Database Server

Restart the database server and check the logs.

MySQL helpfully tells us when SSL is active:
```
[Server] Channel mysql_main configured to support TLS.
```

MySQL also warns us when the CA certificate is self-signed:
```
[Server] CA certificate ca.pem is self signed.
```

Wait, `ca.pem` is not what we named our CA certificate file! It turns out that MySQL generates its own self-signed certificates if we don't configure your own. MySQL also silently ignores files in its configuration folders if it doesn't like them, for example files whose extension is not `.cnf`. If you see log files referring to `ca.pem` instead of the path to `ca_cert.pem` you configured, it means your configuration was not read.

On the other hand, MariaDB seems to only log errors when it comes to SSL configuration. We will see some if, for example, we are using Docker Compose, and we forgot that `docker compose restart` does not mount newly specified volumes, so the database server could not find any of the key and certificate files in the new `/certs` volume. Just a hypothetical.

At this point, it's *possible* to connect with SSL, but it's not *required*. The good news is that's exactly what we (I) wanted, because SSL requirements can be set individually per database user, so we can set up a test user to make sure this all works. Or we could appropriate an existing user used by a service nobody will notice temporarily disappearing because something was misconfigured. Again, just a hypothetical.

Before we can start requiring SSL, we need to update places that connect to our database server.

# 3. Client (PHP) Configuration

Alright, this is where a lot of the online advice gets really bad. So, here's the deal.

We know that a client downloads the server certificate and checks whether it was signed by a trusted CA. How does the client know a CA is trusted? Operating systems come pre-installed with CA certificates that are trusted by the vendor of the operating system. These CAs tend to be commercial, so if you misunderstood my earlier comment to be an encouragement and splurged money on certificates from a commercial CA, it might just work out-of-the-box. However, I have no money (unless you give me some, [wink wink nudge nudge](https://ko-fi.com/chylex)), so I haven't actually tested the hypothesis that things will be easier for you if you pay for a certificate.

Any CA we made up in the course of this tutorial will certainly not be trusted by any operating system vendor. You could use a ~~magical incantation~~ command to install our self-signed CA certificate onto the entire server. Do not. Instead, both MySQLi and PDO let us set a path to the CA certificate file before the connection is created. The provided certificate will become trusted in the context of our database connection, and will be used to verify the signature of the server certificate.

Let's look at some examples. We will assume a folder structure with an `app` folder that is the root of your PHP application, and a `secrets` folder next to it where we can safely store secrets without any way for visitors to access them:
- app/
  - index.php
- secrets/
  - ca_cert.pem

While there is no harm in putting your CA certificate somewhere your visitors could access it, there is no reason to expose them either. Besides, we might want to put *actual secrets* there later.

All examples use paths relative to the PHP script file. If we have full control over the PHP server, we can place secrets into the `/certs` folder like in the example configuration for the database server. In my case, I self-host my database server, but some of my websites are on managed web hosting where this isn't possible.

### MySQLi

**Before:**
```php
$db = new mysqli(DB_HOSTNAME, DB_USERNAME, DB_PASSWORD, DB_DATABASE);
```

**After:**
```php
$db = mysqli_init();
$db->ssl_set(null, null, '../secrets/ca_cert.pem', null, null);
$db->real_connect(DB_HOSTNAME, DB_USERNAME, DB_PASSWORD, DB_DATABASE);
```

The `mysqli_init` function, unlike the `mysqli` constructor, lets us configure the connection before it is established.

The `ssl_set` function has a bunch of optional parameters. If we just want to get SSL working and be done with it, we only need to set the third one to the path to the CA certificate file.

The `real_connect` function establishes a connection to the server. There is an optional [flags argument](https://www.php.net/manual/en/mysqli.real-connect.php) which has an interesting option. This is what the documentation says:
- `MYSQLI_CLIENT_SSL`: Use SSL (encryption)

It looks like you need `MYSQLI_CLIENT_SSL`, but the documentation page on [mysqli constants](https://www.php.net/manual/en/mysqli.constants.php) expands the description with:
- `MYSQL_CLIENT_SSL`: Use SSL (encrypted protocol). This option should not be set by application programs; it is set internally in the MySQL client library

The end goal is to configure the *database server* to require SSL for your `DB_USERNAME`, so we will be sure SSL is active even when we don't specify the `MYSQLI_CLIENT_SSL` flag as half of the documentation suggests.

For the sake of completeness, you should know about a few footguns:
- The `mysqli::real_connect` has another flag: `MYSQLI_CLIENT_SSL_DONT_VERIFY_SERVER_CERT`
- The `mysqli::options` has a boolean option: `MYSQLI_OPT_SSL_VERIFY_SERVER_CERT`

Do not touch either of these. We will go over why disabling verification is a terrible idea, and even setting `MYSQLI_OPT_SSL_VERIFY_SERVER_CERT` to `true` is unnecessary because verification is done by default.

### PDO

**Before:**
```php
$db = new PDO('mysql:host='.DB_HOSTNAME.';dbname='.DB_DATABASE.';charset=utf8mb4', DB_USERNAME, DB_PASSWORD);
```

**After:**
```php
$db = new PDO('mysql:host='.DB_HOSTNAME.';dbname='.DB_DATABASE.';charset=utf8mb4', DB_USERNAME, DB_PASSWORD, [
    PDO::MYSQL_ATTR_SSL_CA => '../secrets/ca_cert.pem'
]);
```

The last parameter for the `PDO` constructor is an associative array of options. The `PDO::MYSQL_ATTR_SSL_CA` option is the path to the CA certificate file.

For the sake of completeness, there is also another option, `PDO::MYSQL_ATTR_SSL_VERIFY_SERVER_CERT`. Do not touch it. We will go over why disabling verification is a terrible idea, and even setting it to `true` is unnecessary because verification is done by default.

## Test SSL Connection

After we connect to the database server, we can test whether SSL is working correctly by running this SQL command: `SHOW STATUS LIKE 'Ssl_%'`

The following examples will print out a few interesting status variables:
- `Ssl_version` is the version of the SSL protocol. The current standard at the time of writing is `TLSv1.3`, which came out in 2018. If your version is lower, update your software.
- `Ssl_cipher` is the symmetric encryption cipher used for the connection.
- `Ssl_server_not_after` is the expiry date of the server certificate.

### MySQLi

```php
foreach ($db->query('SHOW STATUS LIKE \'Ssl_%\'')->fetch_all(MYSQLI_ASSOC) as $row) {
  echo $row['Variable_name'].': '.$row['Value'].'<br>';
}
```

### PDO

```php
foreach ($db->query('SHOW STATUS LIKE \'Ssl_%\'', PDO::FETCH_ASSOC)->fetchAll() as $row) {
  echo $row['Variable_name'].': '.$row['Value'].'<br>';
}
```

## Use Client Key & Certificate

For most people, just getting SSL to work at all is enough. However, if we wanted to strengthen security even more, we could use a client key and certificate.

Similarly to how the client can verify the server's identity using the server certificate, the server is able to verify the client's identity using the client certificate. Assuming we have a client key and certificate, we will need to put the `client_key.pem` and `client_cert.pem` files somewhere our PHP script can access them — for example, into the `secrets` folder, next to the `ca_cert.pem` file. The rest is easy — we just add a few additional arguments or options in the functions we are already calling.

### MySQLi

**Before:**
```php
$db = mysqli_init();
$db->ssl_set(null, null, '../secrets/ca_cert.pem', null, null);
$db->real_connect(DB_HOSTNAME, DB_USERNAME, DB_PASSWORD, DB_DATABASE);
```

**After:**
```php
$db = mysqli_init();
$db->ssl_set('../secrets/client_key.pem', '../secrets/client_cert.pem', '../secrets/ca_cert.pem', null, null);
$db->real_connect(DB_HOSTNAME, DB_USERNAME, DB_PASSWORD, DB_DATABASE);
```

### PDO

**Before:**
```php
$db = new PDO('mysql:host='.DB_HOSTNAME.';dbname='.DB_DATABASE.';charset=utf8mb4', DB_USERNAME, DB_PASSWORD, [
    PDO::MYSQL_ATTR_SSL_CA => '../secrets/ca_cert.pem'
]);
```

**After:**
```php
$db = new PDO('mysql:host='.DB_HOSTNAME.';dbname='.DB_DATABASE.';charset=utf8mb4', DB_USERNAME, DB_PASSWORD, [
    PDO::MYSQL_ATTR_SSL_CA   => '../secrets/ca_cert.pem',
    PDO::MYSQL_ATTR_SSL_CERT => '../secrets/client_cert.pem',
    PDO::MYSQL_ATTR_SSL_KEY  => '../secrets/client_key.pem',
]);
```

## Require SSL for Database User

With SSL working, we should require a user on the database server to use SSL for every connection.
```sql
ALTER USER 'username'@'%' REQUIRE SSL
```

The next, optional step could be to require the database user to connect with any valid client certificate.
```sql
ALTER USER 'username'@'%' REQUIRE X509
```

We could require client certificates to have a specific "subject" (contents of the `-subj` argument earlier). If we took the earlier example command for generating a client certificate literally, the subject of the certificate would be `/C=US/O=organization/OU=organizational_unit/CN=client_name` and the SQL command to require it would look like this:
```sql
ALTER USER 'username'@'%' REQUIRE SUBJECT '/C=US/O=organization/OU=organizational_unit/CN=client_name'
```

Finally, we could not only require a specific "subject" for the client certificate, but also for the CA certificate that signed it. Again, using the earlier example literally, if the subject of the CA certificate is `/C=US/O=organization/OU=organizational_unit/CN=common_name` then the SQL command will look like this:
```sql
ALTER USER 'username'@'%' REQUIRE SUBJECT '/C=US/O=organization/OU=organizational_unit/CN=client_name' AND ISSUER '/C=US/O=organization/OU=organizational_unit/CN=common_name'
```

Actually, I lied — there's even more possibilities. We could, for example, require the client to use a specific cipher. [MariaDB documentation](https://mariadb.com/kb/en/securing-connections-for-client-and-server/#requiring-tls-for-specific-user-accounts-from-specific-hosts) covers this. However, the defaults — especially with TLSv1.3 — should be fine.

## Do Not Disable Server Certificate Verification

Using the `MYSQLI_CLIENT_SSL_DONT_VERIFY_SERVER_CERT` flag or setting the `PDO::MYSQL_ATTR_SSL_VERIFY_SERVER_CERT` flag to `false` is often recommended by online tutorials or stackoverflow answers if you "run into problems", as a way to "fix those problems".

The only problem that is "fixed" by disabling server certificate verification is bad configuration. Sometimes, this bad configuration comes from the tutorial or answer itself, such as setting the path to the CA certificate to a file that does not exist, `/dev/null`, or complete nonsense like `true`.

Although you *will* get an SSL connection if you disable verification, you will have eliminated one of its key guarantees, which is that you can trust the server. If you configure things correctly and establish trust, then if at a later point your network gets attacked and your PHP application starts connecting to a malicious server, those connections will fail because a malicious server is unable to provide a server certificate signed by your CA.

If anyone has a legitimate reason to disable server certificate verification, do let me know in the comments.

# 4. Performance

When we enable SSL, we lose some performance because the client and server have to do some additional work. Out of curiosity, I measured how long it takes to establish a connection to the database server with various compression algorithms — including RSA with various key sizes, in case you were curious — or cannot use Ed25519 for some reason, and are stuck with RSA. My web server is on a shared web hosting, and my database server is self-hosted. I took 200 samples for every configuration, and used [Statistics Kingdom](https://www.statskingdom.com) to make a box plot:

![Box plot showing the performance of No SSL, Ed25519, and RSA with 2048-bit, 3072-bit, and 4096-bit key sizes.]({{ '/assets/img/ultimate-guide-to-mysql-ssl/performance.png' | relative_url }})

The same plot in table form, ordered by median time:

|   Method   |     Min |      Q1 |  Median |      Q3 |     Max |
|:----------:|--------:|--------:|--------:|--------:|--------:|
|   No SSL   |  8.5 ms |  8.7 ms |  8.8 ms |  9.6 ms | 11.0 ms |
| RSA (2048) | 12.8 ms | 13.3 ms | 13.8 ms | 15.9 ms | 18.9 ms |
|  Ed25519   | 12.8 ms | 13.5 ms | 16.6 ms | 18.0 ms | 19.6 ms |
| RSA (3072) | 14.8 ms | 15.6 ms | 17.6 ms | 20.1 ms | 21.7 ms |
| RSA (4096) | 17.4 ms | 18.4 ms | 20.5 ms | 23.2 ms | 25.1 ms |

While it is of course fastest to not use SSL at all, in my opinion, Ed25519 is a great balance of performance and security.

Take these results with a grain of salt; always do your own measurements on whatever hardware and network connection *you* have, to get an idea of the actual impact enabling SSL will have on your website.

Note that I did not measure the performance impact of encrypting and decrypting queries and results. I don't typically deal with amounts of data where I would expect any noticeable degradation in performance, and this post has already taken too much of my time, so I'm fine stopping here and leaving the rest as an exercise for the reader.

# 5. Wow, Security

I hope this has been helpful. If you noticed any problems with the post, don't hesitate to post a comment.

If this post saved you some frustration (although probably not time, considering its length), you can share it and/or support me on [Ko-fi](https://ko-fi.com/chylex).
