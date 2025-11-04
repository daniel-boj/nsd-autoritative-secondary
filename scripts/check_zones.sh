#!/bin/bash

for zonefile in /etc/nsd/zones/*.zone; do
    zone=$(basename "$zonefile" .zone)
    if nsd-checkzone "$zone" "$zonefile"; then
        echo "$zone - OK"
    else
        echo "$zone - ERROR"
    fi
done
