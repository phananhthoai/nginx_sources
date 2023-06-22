#!/usr/bin/env bash
set -e

exec 3>&1

CONF_ROOT_PATH=${CONF_ROOT_PATH:-/etc/nginx}
CONFIG_PATH=${CONFIG_PATH:-${CONF_ROOT_PATH}/nginx.conf}

if [ -f ${CONFIG_PATH} ]; then
  sed -i -E 's/^(\s+)(gzip .*?)$/\1# \2/g' ${CONFIG_PATH}
  sed -i -E 's/(^\s*user).*;/\1 '${RUN_AS:-www-data}';/' ${CONFIG_PATH}
  sed -i -E 's/(^\s*worker_processes).*;/\1 '${WORKER_PROCESSES:-auto}';/' ${CONFIG_PATH}
  sed -i -E 's/(^\s+)# ?(multi_accept).*;/\1\2 '${MULTI_ACCEPT:-on}';/' ${CONFIG_PATH}
  sed -i -E 's/(^\s+worker_connections).*;/\1 '${WORKER_CONNECTIONS:-10240}';/' ${CONFIG_PATH}
fi

CONF_ROOT_PATH=${CONF_ROOT_PATH:-/etc/nginx}
ROUTES_PATH=${ROUTES_PATH:-${CONF_ROOT_PATH}/routes.d}
ROUTE_ACCESS_LOG_PATH=${ROUTE_ACCESS_LOG_PATH:-${ROUTES_PATH}/access_log.conf}

if [ -f ${ROUTE_ACCESS_LOG_PATH} ] && ! [ -z ${ACCESS_LOG} ]; then
  sed -i -E 's|^(access_log .*?) .*?$|\1 '${ACCESS_LOG}';|g' ${ROUTE_ACCESS_LOG_PATH}
fi

CONF_ROOT_PATH=${CONF_ROOT_PATH:-/etc/nginx}
MODULE_PATH=${MODULE_PATH:-${CONF_ROOT_PATH}/modules}
MODULE_AVAILABLE_PATH=${MODULE_AVAILABLE_PATH:-${CONF_ROOT_PATH}/modules-available}
MODULE_ENABLED_PATH=${MODULE_ENABLED_PATH:-${CONF_ROOT_PATH}/modules-enabled}

for item in $(find ${MODULE_PATH} -maxdepth 1 -type f -name "*.so"); do
  name=$(basename ${item} .so)
  if [[ ${name} =~ ^ngx_ ]]; then
    echo "load_module ${item};" | tee ${MODULE_AVAILABLE_PATH}/load_module_${name}.conf >>/dev/null
    if ! [ -s ${MODULE_ENABLED_PATH}/load_module_${name}.conf ]; then
      ln -s ${MODULE_AVAILABLE_PATH}/load_module_${name}.conf ${MODULE_ENABLED_PATH}/
    fi
  fi
done

CONF_ROOT_PATH=${CONF_ROOT_PATH:-/etc/nginx}
SNIPPET_PATH=${SNIPPET_PATH:-${CONF_ROOT_PATH}/snippets}
CONF_PATH=${CONF_PATH:-${CONF_ROOT_PATH}/conf.d}
ROUTES_PATH=${ROUTES_PATH:-${CONF_ROOT_PATH}/routes.d}

if ! [ -z "${CONF}" ]; then
  file_name="nginx.conf"
  echo "${CONF}" | tee ${CONF_ROOT_PATH}/${file_name} >>/dev/null
  echo >&3 "Writing nginx configuration to file ${CONF_ROOT_PATH}/${file_name} ..."
else
  compgen -v | while read -r name; do
    if [[ ${name} =~ ^([A-Z_]+)_SNIPPET$ ]]; then
      mkdir -p ${SNIPPET_PATH}
      file_name="${BASH_REMATCH[1]~~}.conf"
      echo "${!name}" | tee ${SNIPPET_PATH}/${file_name} >>/dev/null
      echo >&3 "Writing snippet to file ${SNIPPET_PATH}/${file_name} ..."
    elif [[ ${name} =~ ^REMOVE_([A-Z_]+)_CONF$ ]]; then
      file_name="${BASH_REMATCH[1]~~}.conf"
      if [ -f ${CONF_PATH}/${file_name} ]; then
        rm ${CONF_PATH}/${file_name}
        echo >&3 "Removing configuration at ${CONF_PATH}/${file_name} ..."
      fi
    elif [[ ${name} =~ ^([A-Z0-9_]+)_CONF$ ]]; then
      file_name="${BASH_REMATCH[1]~~}.conf"
      echo "${!name}" | tee ${CONF_PATH}/${file_name} >>/dev/null
      echo >&3 "Writing configuration to file ${CONF_PATH}/${file_name} ..."
    elif [[ ${name} =~ ^([A-Z0-9_]+)_ROUTE$ ]]; then
      file_name="${BASH_REMATCH[1]~~}.conf"
      echo "${!name}" | tee ${ROUTES_PATH}/${file_name} >>/dev/null
      echo >&3 "Writing configuration to file ${ROUTES_PATH}/${file_name} ..."
    fi
  done
fi

CONF_ROOT_PATH=${CONF_ROOT_PATH:-/etc/nginx}
CONF_PATH=${CONF_PATH:-${CONF_ROOT_PATH}/conf.d}
TEMPLATES_PATH=${TEMPLATES_PATH:-${CONF_ROOT_PATH}/templates}

DNS_VALID_TIME=${DNS_VALID_TIME:-10}
DNS_TIMEOUT_TIME=${DNS_TIMEOUT_TIME:-3}
DNS_IPV6=${DNS_IPV6:-off}
DNS_CONF_NAME=${DNS_CONF_NAME:-dns.conf}

if ! [ -z ${DNS_ADDRESS} ] || ! [ -z ${DNS_VALID_TIME} ]; then
  system_address=$(cat /etc/resolv.conf | grep -oE 'nameserver +([0-9:.]+)'| awk '{ print $2 }' | xargs)
  address=${DNS_ADDRESS:-${system_address}}

  cat ${TEMPLATES_PATH}/dns.conf | sed "s|{{address}}|${address}|g" | sed "s|{{ipv6}}|${DNS_IPV6}|g" | sed "s|{{valid}}|${DNS_VALID_TIME}|g" | sed "s|{{timeout}}|${DNS_TIMEOUT_TIME}|g" | tee ${CONF_PATH}/${DNS_CONF_NAME} >>/dev/null
  echo >&3 "Writing DNS configuration ([${address}], ${DNS_VALID_TIME}s/${DNS_TIMEOUT_TIME}s) to file ${CONF_PATH}/${DNS_CONF_NAME} ..."
fi

CONF_ROOT_PATH=${CONF_ROOT_PATH:-/etc/nginx}
CONF_PATH=${CONF_PATH:-${CONF_ROOT_PATH}/conf.d}
UPSTREAM_PATH=${UPSTREAM_PATH:-${CONF_ROOT_PATH}/upstreams.d}
ROUTES_PATH=${ROUTES_PATH:-${CONF_ROOT_PATH}/routes.d}
TEMPLATES_PATH=${TEMPLATES_PATH:-${CONF_ROOT_PATH}/templates}

CHECK_PROXY_UPSTREAM=${CHECK_PROXY_UPSTREAM:-1}
PROXY_NEXT_TIMEOUT=${PROXY_NEXT_TIMEOUT:-1}
PROXY_CONNECT_TIMEOUT=${PROXY_CONNECT_TIMEOUT:-$(expr ${PROXY_NEXT_TIMEOUT} \* 3)}

if ! [ -z "${PROXY_MAP}" ]; then
  i=0
  echo "${PROXY_MAP}" | while read -r line; do
    if [ -z "${line}" ]; then
      continue
    fi
    ((i++)) || true
    path=/
    upstream_scheme=http
    upstream_host=${line}
    upstream_port=80
    upstream_path=
    if [[ ${upstream_host} =~ ^(.+)\ =\>\ (.+)$ ]]; then
      path=${BASH_REMATCH[1]}
      upstream_host=${BASH_REMATCH[2]}
    fi
    if [[ ${upstream_host} =~ ^([^:/]+)://(.+)$ ]]; then
      upstream_scheme=${BASH_REMATCH[1]}
      upstream_host=${BASH_REMATCH[2]}
      if [[ ${upstream_scheme} =~ ^(http|ws)$ ]]; then
        upstream_port=80
      elif [[ ${upstream_scheme} =~ ^(http|ws)s$ ]]; then
        upstream_port=443
      else
        echo "Upstream scheme ${upstream_scheme} "
      fi
    fi
    if [[ ${upstream_host} =~ ^([^/]+)/(.*)$ ]]; then
      upstream_host=${BASH_REMATCH[1]}
      upstream_path=/${BASH_REMATCH[2]}
    fi
    if [[ ${upstream_host} =~ ^([^:]+):(.+)$ ]]; then
      upstream_host=${BASH_REMATCH[1]}
      upstream_port=${BASH_REMATCH[2]}
    fi
    upstream_addrs=
    if [[ ${upstream_host} =~ ^[0-9.:]+$ ]]; then
      upstream_addrs=${upstream_host}
    else
      if [ ${CHECK_PROXY_UPSTREAM} == 1 ]; then
        printf >&3 "Waiting for ${upstream_host} can be resolved ..."
        success=0
        while [ ${success} == 0 ]; do
          for search in $(cat /etc/resolv.conf | grep -oP '^search \K.+$' | xargs -n 1) ''; do
            _host=${upstream_host}
            if ! [ -z ${search} ]; then
              _host="${upstream_host}.${search}"
            fi
            if [ $(dig +short ${_host} | wc -l) -gt 0 ]; then
              success=1
              upstream_addrs=$(dig +short ${_host})
              echo >&3 ' OK !'
              break
            fi
          done
          if [ ${success} == 0 ]; then
            sleep 1
            printf >&3 '.'
          fi
        done
      fi
    fi
    for upstream_addr in ${upstream_addrs}; do
      if [[ ${upstream_addr} =~ ^[0-9.]+$ ]]; then
        if [ ${CHECK_PROXY_UPSTREAM} == 1 ]; then
          printf >&3 "Waiting for ${upstream_addr}:${upstream_port} (${upstream_host}) to be ready ..."
          while ! nc -z ${upstream_addr} ${upstream_port}; do
            sleep 1
            printf >&3'.'
          done
          echo >&3' OK !'
        fi
      fi
    done
    cat ${TEMPLATES_PATH}/upstream.conf | sed "s|{{index}}|${i}|g" | sed "s|{{upstream_host}}|${upstream_host}|g" | sed "s|{{upstream_port}}|${upstream_port}|g" | tee ${UPSTREAM_PATH}/upsteam_${i}.conf >>/dev/null
    cat ${TEMPLATES_PATH}/proxy.conf | sed "s|{{index}}|${i}|g" | sed "s|{{path}}|${path}|g" | sed "s|{{upstream_scheme}}|${upstream_scheme}|g" | sed "s|{{upstream_path}}|${upstream_path}|g" | sed "s|{{connect_timeout}}|${PROXY_CONNECT_TIMEOUT}|g" | sed "s|{{next_timeout}}|${PROXY_NEXT_TIMEOUT}|g" | tee ${ROUTES_PATH}/route_${i}.conf >>/dev/null
    if ! [ -z ${upstream_path} ]; then
      sed -i -E 's/^(\s+)# (rewrite .*?)$/\1\2/g' ${ROUTES_PATH}/route_${i}.conf      
    fi
  done
fi

CONF_ROOT_PATH=${CONF_ROOT_PATH:-/etc/nginx}
CONF_PATH=${CONF_PATH:-${CONF_ROOT_PATH}/conf.d}

if ! [ -z ${ENABLE_GZIP} ]; then
  sed -i -E 's/^(#\s*)?(include\s+snippets\/gzip\.conf;)$/\2/g' $CONF_PATH/common.conf
fi

if ! [ -z ${ENABLE_BROTLI} ]; then
  sed -i -E 's/^(#\s*)?(include\s+snippets\/brotli\.conf;)$/\2/g' $CONF_PATH/common.conf
fi

if ! [ -z ${TRACE_PROXY} ]; then
  /dist/mitmweb/mitmweb --no-web-open-browser --mode upstream:http://localhost &
  for item in 8080 8081; do
    while ! nc -z localhost ${item}; do
      sleep 1
    done
  done
fi

nginx -t

exec ${@}
