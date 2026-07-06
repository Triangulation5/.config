#!/bin/bash

pkill swaync
pkill qs

qs -p ~/.config/quickshell/pill/shell.qml & disown
/usr/bin/swaync & disown
