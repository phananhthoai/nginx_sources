FROM ubuntu:20.04
RUN apt-get update \
    && apt-get install -y nginx curl dnsutils netcat iputils-ping

WORKDIR /etc/nginx
RUN curl https://getmic.ro | bash
RUN mv ./micro /usr/local/bin
COPY conf.d conf.d
COPY modules modules
COPY modules-available modules-available
COPY modules-enabled modules-enabled
COPY routes.d routes.d
COPY sites-available sites-available
COPY sites-enabled sites-enabled
COPY snippets snippets
COPY templates templates
COPY upstreams.d upstreams.d
COPY init.sh /
RUN rm -f /etc/nginx/modules-enabled/50-mod-http-auth-pam.conf
RUN rm -f /etc/nginx/modules-enabled/50-mod-http-echo.conf
RUN rm -f /etc/nginx/modules-enabled/50-mod-http-geoip2.conf
RUN rm -f /etc/nginx/modules-enabled/50-mod-http-headers-more-filter.conf
RUN rm -f /etc/nginx/modules-enabled/50-mod-http-subs-filter.conf
RUN rm -f /etc/nginx/modules-enabled/50-mod-http-upstream-fair.conf
RUN rm -f /etc/nginx/modules-enabled/70-mod-stream-geoip2.conf
RUN ln -sf /dev/stdout /var/log/nginx/error.log
RUN chmod -R 700 /init.sh
RUN rm -rf /etc/nginx/sites-enabled/default
EXPOSE 80
CMD ["/init.sh", "nginx"]
