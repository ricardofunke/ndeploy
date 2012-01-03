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
}

first_param="${@:1}"
if [[ $# -eq 0 || "${first_param:0:1}" != "-" ]]; then show_usage; exit 1; fi

SHORTOPTS="d:u:g:H:h"
LONGOPTS="dir:,tomcat-user:,tomcat-group:,tomcat-home:,help"

ARGS=$(getopt --name $0 --longoptions="$LONGOPTS" --options="$SHORTOPTS" -- "$@")

eval set -- "$ARGS"

while [ $# -gt 0 ]; do
   case "$1" in
      -d|--dir)                 shift; CD_HOME=${1%/} ;;
      -u|--tomcat-user)         shift; TOMCAT_USER=${1%/} ;;
      -g|--tomcat-group)        shift; TOMCAT_GROUP=${1%/} ;;
      -H|--tomcat-home)         shift; TOMCAT_HOME=${1%/} ;;
      -h|--help)                show_usage; exit 0 ;;
      --)                       shift; break ;;
      *)                        show_usage; exit 1 ;;
    esac
    shift
done

CD_HOME=${CD_HOME:=/opt/clusterdeployer}
TOMCAT_USER=${TOMCAT_USER:=tomcat}
TOMCAT_GROUP=${TOMCAT_GROUP:=$TOMCAT_USER}
TOMCAT_HOME=${TOMCAT_HOME:=/opt/tomcat}

# Checking for a new version (by @pmalves ;)
rm -rf .tmp
mkdir -p .tmp/dist

wget --no-check-certificate 'https://github.com/ricardofunke/clusterdeployer/raw/master/clusterdeployer-install.sh' -P .tmp -o /dev/null

if ! diff $0 .tmp/clusterdeployer-install.sh >/dev/null ; then
  echo
  echo -n "There's a new clusterdeployer-install version available. Do you want to upgrade? (y/N) "
  read -e answer

  case $answer in
	 [Yy]* ) cp .tmp/clusterdeployer-install.sh $0; echo "Upgrade successfull. Rerun"; exit 0;;
  esac

fi

rm -rf .tmp

useradd -r -d ${CD_HOME} -m -g ${TOMCAT_GROUP} clusterdeployer
tomcat_home="$(su -l $TOMCAT_USER -s /bin/bash -c 'echo $HOME')"

echo 'umask 0002' >> ~clusterdeployer/.bashrc
#echo 'umask 0002' >> ${tomcat_home}/.bashrc

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

         su -l clusterdeployer -c "rsync -rlpgDz --del \"${app}\" \"${TOMCAT_DEPLOY_DIR}\"" &

         for node in "${POOL[@]}"; do

            su -l clusterdeployer -c "rsync -rlpgDz --del \"${app}\" ${node}:\"${TOMCAT_DEPLOY_DIR}\"" &

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
TOMCAT_DEPLOY_DIR="${TOMCAT_HOME}/webapps"

EOF
cat <<'EOF'
function undeploy {

   app="${TOMCAT_DEPLOY_DIR}/${1##/*}"
   app="${app%/}"

   if [[ -a "$app" ]]; then

      su -l clusterdeployer -c "rm -rf \"$app\""

      for node in "${POOL[@]}"; do

         su -l clusterdeployer -c "ssh \"${node}\" rm -rf \"$app\""

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
     bash clusterdeployer.sh 2> clusterdeployer.log & 
...
stop)
   fuser -k ~clusterdeployer/clusterdeployer.sh
...'

echo
echo "- You must also make ssh keys for the \"clusterdeployer\" user in *EACH NODE* of your cluster after install clusterdeployer script in all nodes."
echo
echo "- First create a password for \"clusterdeployer\" user in each of your nodes:"
echo "> passwd clusterdeployer"
echo
echo "- Then, use the commands above using \"clusterdeployer\" user in each of your nodes to create the key:"
echo "> ssk-keygen"
echo "> ssh-copy-id -i ~clusterdeployer/.ssh/id_rsa.pub clusterdeployer@<other_node>"
echo
echo "- After create ssh keys it's good to clean and lock clusterdeployer user password in each of your nodes."
echo "- Use the commands above using root user to do that:"
echo "> passwd -d clusterdeployer"
echo "> passwd -l clusterdeployer"
echo
echo ":: ATTENTION! Don't forget to insert de nodes in the POOL variable in the /opt/clusterdeployer/clusterdeployer.sh and /opt/clusterdeployer/clusterundeployer.sh scripts!"
echo

