#!/bin/bash

NODES=() # Put all other nodes but this local machine inside the parentheses separated by spaces
TOMCAT_HOME="" # Put your Tomcat dir inside the quotation marks
CLUSTER_DEPLOY_DIR="${TOMCAT_HOME}/ndeploy/deploy"
TOMCAT_DEPLOY_DIR="${TOMCAT_HOME}/webapps"

show_usage() {
  echo "Usage: $0 <options>"
  echo
  echo "Options:"
  echo -e " -d, --daemon \t\t\t\t\t\t Daemon mode monitoring $CLUSTER_DEPLOY_DIR directory."
  echo -e " -i, --install, --deploy <application.war> \t\t Deploy .war application."
  echo -e " -u, --uninstall, --undeploy <application.war> \t\t Undeploy .war application."
  echo -e " -h, --help \t\t\t\t\t\t Show this message."
}

deploy() {
  rsync $opts --del "$1" "${TOMCAT_DEPLOY_DIR}" &

  for node in "${NODES[@]}"; do
    tar -c "$1" | ./nc.openbsd -q 0 $node 3300 &
  done

  wait
}

undeploy() {
  app="${TOMCAT_DEPLOY_DIR}/${1##*/}"
  app="${app%/}"

  if [[ -a "$app" ]]; then

    rm -rf "$app"

    for node in "${NODES[@]}"; do
      ssh "$node" rm -rf "$app"
    done

  else
    echo "ERROR: The application $1 does not exist!" >&2
    exit 1
  fi
}

daemon_mode() {
  ./nc.openbsd -l -k -p 3300 | tar x -C "$TOMCAT_DEPLOY_DIR" &

  while true; do

    if [[ $(ls -A "${CLUSTER_DEPLOY_DIR}") ]]; then

      for app in "${CLUSTER_DEPLOY_DIR}"/*; do
        deploy "${app}"
        rm -rf "${app}"
      done

    fi

    sleep 5
  done
}

first_param="${@:1}"
if [[ $# -eq 0 || "${first_param:0:1}" != "-" ]]; then show_usage; exit 1; fi

SHORTOPTS="di:u:h"
LONGOPTS="daemon,install:,deploy:,uninstall:,undeploy:,help"

ARGS=$(getopt --name $0 --longoptions="$LONGOPTS" --options="$SHORTOPTS" -- "$@")
eval set -- "$ARGS"

while true; do
  case "$1" in
    -d|--daemon)			daemon_mode;		shift		;;
    -i|--install|--deploy)		deploy "$2";		shift 2		;;
    -u|--uninstall|--undeploy)		undeploy "$2";		shift 2		;;
    -h|--help)				show_usage;		exit 0		;;
    --)					shift;			break		;;
    *)					show_usage;		exit 1		;;
  esac
done
