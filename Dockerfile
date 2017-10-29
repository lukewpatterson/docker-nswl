# See https://docs.citrix.com/en-us/netscaler/11/system/web-server-logging/installing-netscaler-web-logging-client.html
# for supported platforms.  CentOS seemed pretty close.
FROM centos:7.4.1708@sha256:2d0187e394cbd2b72c1b3a75b77cf9f5cab2255d279a529f14af8cabf4ca362d

RUN yum --assumeyes install glibc.i686 expect && yum clean all && expect -version
COPY docker_startup.sh /

ENV CONF_VOLUME=/conf
VOLUME $CONF_VOLUME
ENV CONF_FILE=$CONF_VOLUME/log.before-addns.conf
COPY log.default.conf $CONF_FILE

ONBUILD ENV LOGS_VOLUME=/logs
ONBUILD VOLUME $LOGS_VOLUME
ENV NSWL_RPM=nswl_linux-*.rpm
ONBUILD COPY $NSWL_RPM /
ONBUILD RUN rpm --install $NSWL_RPM && rm $NSWL_RPM && $NSWL -version
ENV NSWL /usr/local/netscaler/bin/nswl
# so logs will be relative to here
ONBUILD WORKDIR $LOGS_VOLUME

ENV NS_USERID nsroot
ENV NS_PASSWORD nsroot

CMD ["/docker_startup.sh"]
