#!/bin/bash

function show_usage {
   echo "Usage: $0 [options ...]"
   echo
   echo "Options:"
   echo -e " -d --dir \t\t ClusterDeployer Home (default: /opt/clusterdeployer)"
   echo -e " -u --tomcat-user \t Tomcat user (default: tomcat)"
   echo -e " -g --tomcat-group \t Tomcat group (default: tomcat)"
   echo -e " -H --tomcat-home \t Tomcat home (default: /opt/tomcat)"
   echo -e " -h --help \t\t Print this help message."
   exit 1
}

[ $# -eq 0 ] && show_usage

SHORTOPTS="d:u:g:H:h"
LONGOPTS="dir:,tomcat-user:,tomcat-group:,tomcat-home:,help"

ARGS=$(getopt --name $0 --longoptions="$LONGOPTS" --options="$SHORTOPTS" -- "$@")

eval set -- "$ARGS"

while [ $# -gt 0 ]; do
   case "$1" in
      -d|--dir)                 CD_HOME=$2; shift ;;
      -u|--tomcat-user)         TOMCAT_USER=$2; shift ;;
      -g|--tomcat-group)        TOMCAT_GROUP=$2; shift ;;
      -H|--tomcat-home)         TOMCAT_HOME=$2; shift ;;
      -h|--help)                show_usage ;;
      --)                       shift; break ;;
      *)                        show_usage; break ;;
    esac
    shift
done

CD_HOME=${CD_HOME:=/opt/clusterdeployer}
TOMCAT_USER=${TOMCAT_USER:=tomcat}
TOMCAT_GROUP=${TOMCAT_GROUP:=tomcat}
TOMCAT_HOME=${TOMCAT_HOME:=/opt/tomcat}

useradd -r -d ${CD_HOME} -m -g ${TOMCAT_GROUP} clusterdeployer
echo 'umask 0002' >> ~clusterdeployer/.bashrc
echo 'umask 0002' >> ~${TOMCAT_USER}/.bashrc

su -l -s /bin/sh ${TOMCAT_USER} -c "mkdir ${TOMCAT_HOME}/.clusterdeploy"
su -l -s /bin/sh ${TOMCAT_USER} -c "find tomcat*/webapps -maxdepth 1 ! -name ROOT ! -name tunnel-web \
                                    -exec chmod g+w {} -R \;"
{
cat <<'EOF'
#!/bin/bash

echo $$ > ~clusterdeployer/pid
EOF
cat <<EOF
POOL=($NODES)
TOMCAT_HOME="${TOMCAT_HOME}"
CLUSTER_DEPLOY_DIR="${TOMCAT_HOME}"/.clusterdeploy
TOMCAT_DEPLOY_DIR="${TOMCAT_HOME}"/webapps
USER=clusterdeployer
EOF
cat <<'EOF'
while true; do
   
   if [[ $(ls -A "${CLUSTER_DEPLOY_DIR}") ]]; then

      for app in "${CLUSTER_DEPLOY_DIR}"/*; do

         rsync -rlpgDz --del "${app}" "${TOMCAT_DEPLOY_DIR}"

         for node in "${POOL[@]}"; do

            rsync -rlpgDz --del "${app}" ${node}:"${TOMCAT_DEPLOY_DIR}"

         done

         rm -rf "${app}"

      done

   fi

   sleep 5

done
EOF
} > ~clusterdeployer/clusterdeployer.sh 

chown clusterdeployer:root ~clusterdeployer -R

echo "Copy these lines to your tomcat's init script:"
echo \
'...
start)
   su -l clusterdeployer -c "bash clusterdeployer.sh 2> clusterdeployer.log" &
...
stop)
   kill -9 $(echo ~clusterdeployer/pid)
...'

echo "You must also make ssh keys for the clusterdeployer user in each node of your cluster."
echo "See ssk-keygen and ssh-copy-id commands to do so."
