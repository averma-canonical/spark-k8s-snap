#!/bin/bash
set -x
echo "KUBECONFIG: $KUBECONFIG"
if [[ ! -n "$KUBECONFIG" ]]; then
  KUBECONFIG="$SNAP_REAL_HOME/.kube/config"
fi

exec $1 --kubeconfig=$KUBECONFIG "$@"