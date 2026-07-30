#!/bin/bash

pkill qs

qs -p ~/.config/quickshell/pill/shell.qml & disown
qs -p ~/.config/quickshell/lock/ & disown
qs -p ~/.config/quickshell/screencorner/ & disown
