#!/bin/bash

if [[ ! -n "$KUBECONFIG" ]]; then
  KUBECONFIG="$SNAP_REAL_HOME/.kube/config"
fi

KUBECONFIG=$KUBECONFIG exec "$@"