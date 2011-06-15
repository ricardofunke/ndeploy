#!/bin/bash

function show_usage {
   echo "Usage: $0 [options ...]"
   echo
   echo "Options:"
   echo -e " -d --dir \t\t ClusterDeployer Home (default: /opt/clusterdeployer)"
   echo -e " -u --tomcat-user \t Tomcat user (default: tomcat)"
   echo -e " -g --tomcat-group \t Tomcat group (default: same as --tomcat-user)"
   echo -e " -H --tomcat-home \t Tomcat home (default: /opt/tomcat)"
   echo -e " -h --help \t\t Print this help message."
   exit 1
}

first_param="${@:1}"
[[ $# -eq 0 || "${first_param:0:1}" != "-" ]] && show_usage

SHORTOPTS="d:u:g:H:h"
LONGOPTS="dir:,tomcat-user:,tomcat-group:,tomcat-home:,help"

ARGS=$(getopt --name $0 --longoptions="$LONGOPTS" --options="$SHORTOPTS" -- "$@")

eval set -- "$ARGS"

while [ $# -gt 0 ]; do
   case "$1" in
      -d|--dir)                 ${CD_HOME%/}=$2; shift ;;
      -u|--tomcat-user)         ${TOMCAT_USER%/}=$2; shift ;;
      -g|--tomcat-group)        ${TOMCAT_GROUP%/}=$2; shift ;;
      -H|--tomcat-home)         ${TOMCAT_HOME%/}=$2; shift ;;
      -h|--help)                show_usage ;;
      --)                       shift; break ;;
      *)                        show_usage >&2; break ;;
    esac
    shift
done

CD_HOME=${CD_HOME:=/opt/clusterdeployer}
TOMCAT_USER=${TOMCAT_USER:=tomcat}
TOMCAT_GROUP=${TOMCAT_GROUP:=$TOMCAT_USER}
TOMCAT_HOME=${TOMCAT_HOME:=/opt/tomcat}

useradd -r -d ${CD_HOME} -m -g ${TOMCAT_GROUP} clusterdeployer
echo 'umask 0002' >> ~clusterdeployer/.bashrc
tomcat_home="$(su -l $TOMCAT_USER -s /bin/bash -c 'echo $HOME')"
echo 'umask 0002' >> ${tomcat_home}/.bashrc

su -l -s /bin/bash ${TOMCAT_USER} -c "mkdir ${tomcat_home}/.clusterdeploy"
find ${TOMCAT_HOME}/webapps -maxdepth 1 ! -name ROOT ! -name tunnel-web -exec chmod g+w {} \;

{
cat <<'EOF'
#!/bin/bash

EOF
cat <<EOF
POOL=() # Put the other nodes here separated by spaces, except for local machine
TOMCAT_HOME="${TOMCAT_HOME}"
CLUSTER_DEPLOY_DIR="${tomcat_home}/.clusterdeploy"
TOMCAT_DEPLOY_DIR="${TOMCAT_HOME}/webapps"

EOF
cat <<'EOF'
while true; do
   
   if [[ $(ls -A "${CLUSTER_DEPLOY_DIR}") ]]; then

      for app in "${CLUSTER_DEPLOY_DIR}"/*; do

         rsync -rlpgDz --del "${app}" "${TOMCAT_DEPLOY_DIR}"

         for node in "${POOL[@]}"; do

            rsync -rlpgDz --del "${app}" ${node}:"${TOMCAT_DEPLOY_DIR}" &

         done

         wait
         rm -rf "${app}"

      done

   fi

   sleep 5

done

EOF
} > ~clusterdeployer/clusterdeployer.sh 

{
cat <<EOF
#!/bin/bash

POOL=() # Put the other nodes here separated by spaces, except for local machine
TOMCAT_HOME="${TOMCAT_HOME}"
TOMCAT_DEPLOY_DIR="${tomcat_home}/webapps"

EOF
cat <<'EOF'
function undeploy {

   app="${TOMCAT_DEPLOY_DIR}/${1##/*}"
   app="${app%/}"

   if [[ -d "$app" ]]; then

      rm -rf "$app"

      for node in ${POOL[@]}"; do

         ssh ${node rm -rf "$app"

      done

   else

      echo "ERROR: The application $1 does not exist!" >&2
      exit 1

   fi
}

if [[ $# -gt 1 ]]; then echo 'Error: Undeploy one app at a time!' >&2 ; exit 1; fi

case "$1" in
   -h|--help|'')
      echo "Usage $0 <application>"
      ;;

   *)
      undeploy "$1"
      ;;
esac

EOF
} > ~clusterdeployer/clusterundeployer.sh

chown clusterdeployer:root ~clusterdeployer -R
chmod +x ~clusterdeployer/*.sh

echo "Copy these lines to your tomcat's init script:"
echo \
'...
start)
   [[ ! $( fuser ~clusterdeployer/clusterdeployer.sh  ) ]] &&
     su -l clusterdeployer -c "bash clusterdeployer.sh 2> clusterdeployer.log &" 
...
stop)
   fuser -k ~clusterdeployer/clusterdeployer.sh
...'

echo
echo "You must also make ssh keys for the \"clusterdeployer\" user in each node of your cluster after install clusterdeployer script in all nodes."
echo
echo "Use the commands above using \"clusterdeployer\" user to do that:"
echo "> ssk-keygen"
echo "> ssh-copy-id ~clusterdeployer/.ssh/id_rsa.pub clusterdeployer@<other_node>"
echo
echo "Before crate ssh keys you must define a password to \"clusterdeployer\" user using \"passwd clusterdeployer\" command,"
echo "but after create ssh keys it's good to clean and lock clusterdeployer user password"
echo
echo "Use the commands above using root user to do that:"
echo "> passwd -d clusterdeployer"
echo "> passwd -l clusterdeployer"
echo
echo "Attention! Don't forget to insert de nodes in the POOL variable in the /opt/clusterdeployer/clusterdeployer.sh and /opt/clusterdeployer/clusterundeployer.sh scripts!"

