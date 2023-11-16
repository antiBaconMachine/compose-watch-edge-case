#! /usr/bin/env sh

while true ; do nc -l -q 0 -p 8080 < hello.http ; done