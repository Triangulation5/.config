#!/bin/bash

pkill qs

qs -p ~/.config/quickshell/pill/shell.qml & disown
