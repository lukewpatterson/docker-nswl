# lukewpatterson/nswl
Docker Image of [NetScaler Web Logging (NSWL) Client](https://docs.citrix.com/en-us/netscaler/11/system/web-server-logging.html)

*Note: This image has only been tested on version 11 of NetScaler.*

## Preparation

1. [Download](https://docs.citrix.com/en-us/netscaler/11/system/web-server-logging/installing-netscaler-web-logging-client.html) the Linux NSWL Client package for your NetScaler version.  To prevent you from using NSWL for fun and from living too far into the present, you need an account to download.

1. Place the downloaded client package file alongside a `Dockerfile` containing:
    ```Dockerfile
    FROM lukewpatterson/nswl:11
    ```
    The client package file name must match the pattern `nswl_linux-<VERSION>.rpm`.  The version used in testing was `nswl_linux-11.0-66.11.rpm`.

1. Build the image.

## Configuration

[Configuration Documentation](https://docs.citrix.com/en-us/netscaler/11/system/web-server-logging/customize-logging-on-nswl-client.html)

Configuration can come from a file (`/conf` volume), or from an environmental variable (`CONF_FILE_CONTENTS`).  Must not contain entries created with the ['-addns'](https://docs.citrix.com/en-us/netscaler/11/system/web-server-logging/configuring-nswl-client.html) command.  `-addns` entries are injected automatically using information from `NS_*` environmental variables.

The default value used is:
```
Filter default
begin default
  logFormat               W3C
  logInterval             Hourly
  logFileSizeLimit        10
  logFilenameFormat       Ex%{%y%m%d}t.log
end default

```

## Volumes

* `/conf` - File-based Configuration.  File name must be `log.before-addns.conf`.  The file is not modified during the `-addns` entry creation process, so this volume can be set to [`read-only`](https://docs.docker.com/v17.06/engine/admin/volumes/volumes/#use-a-read-only-volume) if desired.
* `/logs` - Log Files.  [logFilenameFormat](https://docs.citrix.com/en-us/netscaler/11/system/web-server-logging/customize-logging-on-nswl-client.html) paths will be relative to here, unless absolute form (starts with '`/`') specified.  Examples:
    - `logFilenameFormat       Ex%{%y%m%d}t.log` will create logs in `/logs`
    - `logFilenameFormat       some_relative_subdirectory/Ex%{%y%m%d}t.log` will create logs in `/logs/some_relative_subdirectory`
    - `logFilenameFormat       /some_absolute_directory/Ex%{%y%m%d}t.log` will create logs in `/some_absolute_directory`, which won't be written to this volume

## Environmental Variables

* `CONF_FILE_CONTENTS` - Environment-based Configuration.  If set, takes precedence over File-based Configuration.  The entire contents of a multi-line configuration file.
* `addns`-specific variables
    - `NS_IPS` - NetScaler IP(s).  No default value.  Comma-separated list, no spaces.  Examples:
        - `10.1.2.3` specifies 1 NetScaler IP
        - `10.1.2.3,192.168.2.3,10.11.12.13` specifies 3 NetScaler IPs
    - `NS_USERID` - NetScaler User ID.  Default value is `nsroot`.
    - `NS_PASSWORD` - NetScaler Password.  Default value is `nsroot`.

## Demo

Once you've built your custom image, you can run [NetScaler CPX](https://www.citrix.com/products/netscaler-adc/resources/netscaler-cpx-data-sheet.html) locally and see an example NSWL log file.  [Docker Compose](https://docs.docker.com/compose/) must be installed for this demo.

1. Create a file called `nsboot.custom.conf` with this content:
```
# include the entries normally created dynamically by /var/netscaler/bins/docker_startup.sh 
add route 0 0  172.16.0.1
set rnat 192.0.0.0 255.255.255.0 -natip  172.16.0.10
add ssl certkey ns-server-certificate -cert ns-server.cert -key ns-server.key
set tcpprofile nstcp_default_profile mss  1460
# add a load balancing virtual server with 2 backing services, align with compose file values
add lb vserver vserver_1 HTTP 172.16.0.10 8000
add service service_1 172.16.0.11 HTTP 8000
bind lb vserver vserver_1 service_1
add service service_2 172.16.0.12 HTTP 8000
bind lb vserver vserver_1 service_2
# enable weblogging
enable ns feature WL
```
2. Create a `docker-compose.yml` file with this content: 
```yaml
version: '3.4'
services:
  my-nswl:
    image: <YOUR_CUSTOM_IMAGE>
    volumes:
      - ./logs/:/logs/
    environment:
      NS_IPS: 172.16.0.10
    networks:
      nswl_network:
  cpx:
    image: store/citrix/netscalercpx:11.1-53.11@sha256:33f63911e478e2de64fcf1bb0c32d604fafe94923f5b5aa9f15fd9e00dc9cb51
    volumes:
     # set to readonly so /var/netscaler/bins/docker_startup.sh doesn't recreate it and wipe out our customizations
     - ./nsboot.custom.conf:/cpx/nsconfig/nsboot.conf:ro  
    ports:
      - "8000:8000"
    environment:
      EULA: "yes"
      NS_ABORT_ON_FAILED_REGISTRATION: "false"
    networks:
      nswl_network:
        ipv4_address: 172.16.0.10
    privileged: true
  service_1:
    image: jwilder/whoami@sha256:63c36b1b0e855b683daba4f3731692bfdad9dc4b12660efc537e94be441688b5
    hostname: service_1
    ports:
      - "8001:8000"
    networks:
      nswl_network:
        ipv4_address: 172.16.0.11
  service_2:
    image: jwilder/whoami@sha256:63c36b1b0e855b683daba4f3731692bfdad9dc4b12660efc537e94be441688b5
    hostname: service_2
    ports:
      - "8002:8000"
    networks:
      nswl_network:
        ipv4_address: 172.16.0.12
networks:
  nswl_network:
    ipam:
      config:
        - subnet: 172.16.0.0/24
```

3. Run `docker-compose up`.  Give it a little while to start up.  You should see something like this when it's ready:
```shell
cpx_1          ...
cpx_1          | Starting Monit 5.16 daemon
```

4. Browse to (or `curl`) [http://localhost:8000](http://localhost:8000) a few times.  You should see the results alternate between `I'm service_1` and `I'm service_2` as CPX balances the load.

5. Inspect the contents of the `logs/ExYYMMDD.log` file, which was created by NSWL during the previous step.  It might take up to a few minutes for the results to fully appear.  You should see something like this:
```
#Version: 1.0
#Software: Netscaler Web Logging(NSWL)
#Date: 2017-10-29 03:54:56
#Fields: date time c-ip cs-username sc-servicename s-ip s-port cs-method cs-uri-stem cs-uri-query sc-status cs-bytes sc-bytes time-taken cs-version cs(User-Agent) cs(Cookie) cs(Referer) 
2017-10-29 03:54:12 172.16.0.1 - HTTP 172.16.0.11 8000 GET / - 200 78 131 0 HTTP/1.1 curl/7.54.0 - -
2017-10-29 03:54:15 172.16.0.1 - HTTP 172.16.0.12 8000 GET / - 200 78 131 0 HTTP/1.1 curl/7.54.0 - -
2017-10-29 03:54:20 172.16.0.1 - HTTP 172.16.0.11 8000 GET / - 200 78 131 0 HTTP/1.1 curl/7.54.0 - -
```

## Logstash

If you use [Logstash](https://www.elastic.co/products/logstash), you might find this useful.

`docker-compose.yml` file:

```yaml
version: '3.4'
services:
  nswl:
    image: <YOUR_CUSTOM_IMAGE>
    volumes:
      - ./logs/:/logs/
  filebeat:
    image: prima/filebeat:5.3.0
    volumes:
      - ./logs/:/logs/
      - ./filebeat/:/data/
    environment:
      config_filebeat_yml: |
        filebeat.prospectors:
          - input_type: log
            paths:
              - /logs/*.log
        output.logstash:
          hosts: ["<YOUR_LOGSTASH_BEAT_INPUT_URL>"]
    entrypoint:
      - /bin/sh
      - -c
      - >
        echo -n "$$config_filebeat_yml" > /filebeat.yml
        && exec /docker-entrypoint.sh filebeat -e
```

Logstash configuration snippet:

```
input {
  beats {
    port => 5044
  }
}
filter {
  if ([message] =~ /^#/) {
      drop{}
  } else {
    dissect {
      mapping => {
        "message" => "%{date} %{time} %{c-ip} %{cs-username} %{sc-servicename} %{s-ip} %{s-port} %{cs-method} %{cs-uri-stem} %{cs-uri-query} %{sc-status} %{cs-bytes} %{sc-bytes} %{time-taken} %{cs-version} %{cs-header-user-agent} %{cs-header-cookie} %{cs-header-referer}"
      }
      convert_datatype => {
        "s-port" => "int"
        "sc-status" => "int"
        "cs-bytes" => "int"
        "sc-bytes" => "int"
        "time-taken" => "int"
      }
    }
    mutate {
      add_field => {
        "timestamp" => "%{date}T%{time}Z"
      }
    }
    date {
      match => ["[timestamp]", "ISO8601"]
      remove_field => "[timestamp]"
    }
    fingerprint {
      base64encode => true
      concatenate_sources => true
      key => "key"
      method => "SHA1"
      source => ["source", "offset"]
      target => "[@metadata][fingerprint]"
    }
  }
}
output {
  elasticsearch {
    hosts => ["<YOUR_ELASTICSEARCH>"]
    manage_template => false
    index => "nswl-%{+YYYY.MM.dd}"
    document_type => "%{[@metadata][type]}"
    document_id => "%{[@metadata][fingerprint]}"
  }
}
```
