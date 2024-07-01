#!/bin/bash

if [[ ! -n "$KUBECONFIG" ]]; then
  KUBECONFIG="$SNAP_REAL_HOME/.kube/config"
fi

exec $1 --kubeconfig=$KUBECONFIG "$@"