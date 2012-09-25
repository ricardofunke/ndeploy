This script allows you to replicate .war applications deploy to all your application server nodes. It uses SSH with Rsync to do that, and depends of a pair of SSH keys in each node to the replication be possible.

To install, make a copy of this script to all your nodes. I recommend to create a folder called "ndeploy" and copy the ndeploy.sh script inside it.

Next to the script, inside the same "ndeploy" folder, create another folder called "deploy" where the script will watch for .war files to be replicated to all nodes. 

Grant execute permission to the script with "chmod +x ndeploy.sh"

Edit the script and set the NODES variable with all your nodes IP except the local one. Don't forget to do this for all the nodes.

Change the variable APPSRV_HOME to the correct path to your application server, the same of TOMCAT_HOME or JBOSS_HOME, etc.

You must create ssh public keys and distribute between all nodes using the application server user. This is necessary to eliminate the need for password between the nodes. For example, suppose you're using tomcat as the user to run it (the java process), so in the "node1" server, do:

As root:

    # su - tomcat
    
    $ ssh-keygen

Press enter without set any password

    $ ssh-copy-id -i .ssh/id_rsa.pub tomcat@node2

Do the same for all Tomcat nodes you have.

Now you have to make sure that this script will run with Tomcat side-by-side as a deamon. Use the option -d to run the script as a deamon. You can put it in your Tomcat startup script. Remember to use the same user as Tomcat to run this script.

# For Liferay users:

Liferay must be set to deploy the application not to the application server but first to ndeploy.sh "deploy" folder, so that it can copy to all other nodes. The order of deploying will be like this:

1. You'll copy your application to the Liferay deploy folder (or you will upload through Control Panel)
2. Liferay will copy the application to ndeploy.sh folder
3. ndeploy.sh will copy the application to the application server in all nodes locally and remotelly.

To do this, put this property into your portal-ext.properties:

    auto.deploy.dest.dir=/path/to/ndeploy/deploy

Change the value to correspond to the path to the ndeploy.sh deploy folder. You can make this in the Control Panel instead in Control Panel -> Plugins Installation -> Install More Plugins -> Configuration in the "Destination directory" field.

It's all. Let me know if you have any trouble with this installation.
