!#/bin/bash

for zonefile in /etc/nsd/zones/*.zone; do
    zonename=$(basename "$zonefile" .zone)
    echo "Agregando: $zonename"
    nsd-control addzone "$zonename" ".*"
done

nsd-control reconfig
