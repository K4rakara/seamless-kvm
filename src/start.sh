#!/usr/bin/sh

{
  TO_WRITE="export ARG_N=${#};";
  
  I="$((1))";
  for ARG in "${@}"; do
    TO_WRITE="${TO_WRITE}export ARG_${I}=\"${ARG}\";";
    I="$((${I} + 1))";
  done;

  echo "${TO_WRITE}" > /tmp/seamless-kvm-args;
}

systemctl start seamless-kvm.service;
