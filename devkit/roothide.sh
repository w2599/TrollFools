#!/bin/sh

export THEOS=$HOME/theos_roothide
export THEOS_PACKAGE_SCHEME=roothide
export THEOS_DEVICE_IP=192.168.31.158
export THEOS_DEVICE_PORT=54322

if [ "$1" = "1" ]; then
    export package FINALPACKAGE=1
fi


make do