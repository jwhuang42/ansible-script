#!/bin/bash

# Define wait time variable
WAIT_TIME=5

# Function to wait for user input with a timeout
wait_for_input() {
    echo "#############################################################################"
    echo "    Press any key to stop here or wait for $WAIT_TIME seconds to continue    "
    echo "#############################################################################"
    read -t $WAIT_TIME -n 1
    if [ $? = 0 ]; then
        echo "Stopping the script as requested."
        exit 0
    else
        echo
        echo "Continue to next playbook..."
        echo
    fi
}

# Function to check the exit status of ansible-playbook command
check_failure() {
    if [ $? -ne 0 ]; then
        echo "Ansible playbook failed. Exiting script."
        exit 1
    fi
}

echo "################################"
echo "       Set up hadoop user       "
echo "################################"
ansible-playbook book/setup-user.yaml -e ansible_user=root -vv
check_failure
wait_for_input

echo "################################"
echo "     Sync Hadoop ssh keys       "
echo "################################"
ansible-playbook book/sync-host.yaml -vv
check_failure
wait_for_input

echo "################################"
echo "    Install Hadoop Binaries     "
echo "################################"
ansible-playbook book/install-hadoop.yaml -vv
check_failure
wait_for_input

echo "################################"
echo "  Configure and start Zookeeper "
echo "################################"
ansible-playbook book/config-zk.yaml -vv
check_failure
wait_for_input

echo "################################"
echo "     Configure HDFS and YARN    "
echo "################################"
ansible-playbook book/config-hadoop.yaml -vv
check_failure
wait_for_input

echo "######################################"
echo "Initialize and start the HDFS and YARN"
echo "######################################"
ansible-playbook book/provision-hadoop.yaml -vv
check_failure
