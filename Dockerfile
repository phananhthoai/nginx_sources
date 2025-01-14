##### syntax=nobidev/dockerfile
FROM ubuntu:24.04
RUN <<-EOF
   apt-get update 
   apt-get install -y curl dnsutils netcat-openbsd iputils-ping nginx-full libbrotli-dev
EOF
    
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
RUN rm -f /etc/nginx/modules-enabled/50-mod-http-headers-more-filter.conf
RUN rm -f /etc/nginx/modules-enabled/50-mod-http-image-filter.conf
RUN rm -f /etc/nginx/modules-enabled/50-mod-http-xslt-filter.conf
RUN rm -f /etc/nginx/modules-enabled/50-mod-mail.conf
RUN ln -sf /dev/stdout /var/log/nginx/error.log
RUN chmod -R 700 /init.sh
RUN rm -rf /etc/nginx/sites-enabled/default
LABEL maintainer="Devops"
EXPOSE 80
ENTRYPOINT ["/init.sh", "nginx"]

