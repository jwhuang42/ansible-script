## Prerequisite

1. Prepare Ubuntu 22.04 for all VMs, and make sure ssh server is installed and enabled on all related machines

   **Suggestion**: You may want to take a snapshot of each VM at this stage, so you can rollback the state and reinstall
   everything if needed.

1. Make sure you are familiar with
   the [ssh concepts](https://www.digitalocean.com/community/tutorials/ssh-essentials-working-with-ssh-servers-clients-and-keys).

1. set ssh key based authentication\
   **Note**: The assumption is the control machine can ssh to all controlled machine via password, if passwordless
   access is already configured, just see if the `.ssh/config` need to modify.

   - change directory `cd ~/.ssh`.
   - on ansible control machine, run `ssh-keygen -t rsa -b 2048 -f <keyname>` to generate ssh key pair(without
     passphrase).
   - Check the generated public key: `cat ~/.ssh/<keyname>.pub`
   - On each ansible controlled machine (i.e. also called ansible host), run the following command, replace
     the `<pub_key_string>`
     with real key:(Note: you can
     use [ssh-copy-id](https://www.digitalocean.com/community/tutorials/ssh-essentials-working-with-ssh-servers-clients-and-keys#copying-your-public-ssh-key-to-a-server-with-ssh-copy-id)
     instead if you have password access to other VMs)
     ```
     cat <<EOF >> ~/.ssh/authorized_keys
     <pub_key_string>
     EOF
     ```
   - If your key name or username is different from the default one (i.e. key name is not `id_rsa`
     or the user on the control machine and the controlled machines are different), you may need to configure ssh
     client on the control machine via a file at `~/.ssh/config` to access the controlled machines.
     Check [this link](https://www.digitalocean.com/community/tutorials/how-to-configure-custom-connection-options-for-your-ssh-client)
     for more detail.
     A sample config on one of the nodes could look like:
     ```
     Host 192.168.62.141
       Hostname <controlled_node_hostname> # may need to configure /etc/hosts first
       User admin
       PreferredAuthentications publickey
       IdentityFile ~/.ssh/<keyname>
     ```

1. change directory to the ansible project(the location of this .md file) and configure the `hosts` ansible file

    1. Change directory to ansible project hadoop directory `ansible-script/hadoop` (the location of this .md file) on
       the host machine.
   1. Enter the docker container ansible using the "jwhuang42/ansible:8.7.0" image, mount related volumes
      ```
      docker run -it --rm --name ansible -v "$PWD":/work -v "$HOME/.ssh":"/root/.ssh" -v /etc/hosts:/etc/hosts jwhuang42/ansible:8.7.0
      ```
   1. Inside the container
      ```
      # Go to work directory and change owner from 1000 to root
      cd /work && chown root:root ~/.ssh/config && chmod +x deploy-all.sh
      ```
   1. Check and configure the ansible hosts file.
    - Change the VM IP addresses to the real one for Hadoop deployment under the `[nodes]` and `[zk_nodes]` section.
    - Add the IPs of the VMs you intend to install Hadoop under the `[newborn]` section.

## One line Deployment

You can execute the single command `./deploy-all.sh` under the working directory to directly set up a hadoop HA cluster.
The entire process takes about 15 min.
It is highly recommended to check the `conf/hadoop` and `conf/zk` first and see if any modification is needed.

## Step-by-Step Deployment

### Cluster Configuration, Zookeeper set up, and Hadoop Installation
1. Initialize the cluster environment by setting up the keys and install Hadoop manifests.

    - Execute `ansible-playbook book/sync-host.yaml -vv`
        - **Hint**: add `-vvv` argument at the end of the `ansible-playbook` command can help you debug issue.(The
          number of 'v' stands for verbosity, 'vvv' has the highest verbosity)
   - Execute `ansible-playbook book/install-hadoop.yaml -vv`
       - Note: if download artifact from remote repo, it could take up to 15min.
    - Clear the machines under the `[newborn]` section after hadoop installation completes.

1. Configure and launch zookeeper

    - Make sure `[zk_nodes]` contains all nodes to install zookeeper, and has `ansible_host`, `myid` correctly
      configured.
    - Look JVM args in `book/config-zk.yaml` and change if needed.
        - **Note**: Understand what existing argument means first.
   - Execute `ansible-playbook book/config-zk.yaml -vv`

     **Note**: you can use `book/shutdown-zk.yaml` to directly shut down the zookeeper cluster, but make sure all other
     hadoop processes have properly shutdown first.

1. Configure Hadoop

    - Change `hosts` file
        - List all hadoop nodes under `[hadoop_nodes]`
        - List all namenodes under `[namenodes]` (must configure `id`，`rpc_port`，`http_port`)
        - List all datanodes under `[datanodes]`
        - List all journalnodes under `[journalnodes]` (must configure `journal_port`)
        - List all resourcemanagers under `[resourcemanagers]` (must
          configure `id`，`peer_port`，`tracker_port`，`scheduler_port`，`web_port`)
    - Look JVM args in `book/config-hadoop.yaml` and change if needed.
        - **Note**: Understand what existing argument means first.
   - Execute `ansible-playbook book/config-hadoop.yaml -vv`

### Hadoop Provision

If this is the first time start the cluster, check `Start Hadoop cluster for the first time`, otherwise
check `Start Hadoop cluster from the shutdown state`.

#### Start Hadoop cluster for the first time

**Note**: If this script failed in the middle, you would need to delete the hadoop data directory and undone zk format.
So far we only have script to delete
Hadoop data directory: `ansible-playbook book/remove-all-hadoop-data.yaml -vv`

Below is the main script to format and start the cluster for the first time.

```
ansible-playbook book/provision-hadoop.yaml -vv
```

#### Start Hadoop cluster from the shutdown state

```
ansible-playbook book/start-hadoop.yaml -vv
```

### Verify the Web Interface

**Assumption**: ansible control node is a remote linux ubuntu machine without GUI, cluster admin(you) can access
the ansible control node from the local machine.

1. [Set up a ssh tunnel](https://www.digitalocean.com/community/tutorials/ssh-essentials-working-with-ssh-servers-clients-and-keys#configuring-local-tunneling-to-a-server)
   from your local machine to the ansible control node. It should look like:
   ```
   ssh -f -N -L <some_web_port>:my.hadoop<x>:<some_web_port> -L <another_web_port>:my.hadoop<x>:<another_web_port> (-L...) admin@<ansible_control_node_ip>
   ```

1. Check the mapped local port on localhost to visit the corresponding webpage.

### Cluster Shutdown

**Note**: This is probably not needed for production environment, but you may use this during cluster set up test or
upgrade.

The following shutdown guide will close Hadoop cluster with HA YARN and HA HDFS.

1. Check the running processes.
   ```
   ansible 'nodes' -m shell -a '. /etc/profile && jps'
   
   # A fully start HDFS_HA + YARN_HA should have the following result
   # <my.hadoop1 ip> | CHANGED | rc=0 >>
   # 5907 DFSZKFailoverController
   # 5604 DataNode
   # 7863 NameNode
   # 11431 Jps
   # 6602 NodeManager
   # 2987 QuorumPeerMain
   # 3484 JournalNode
   # <my.hadoop3 ip> | CHANGED | rc=0 >>
   # 3760 DataNode
   # 6753 Jps
   # 2897 JournalNode
   # 4114 NodeManager
   # 2653 QuorumPeerMain
   # 4799 ResourceManager
   # <my.hadoop2 ip> | CHANGED | rc=0 >>
   # 4466 DFSZKFailoverController
   # 2643 QuorumPeerMain
   # 4292 DataNode
   # 2886 JournalNode
   # 4168 NameNode
   # 6634 Jps
   # 4702 NodeManager
   # <my.hadoop4 ip> | CHANGED | rc=0 >>
   # 2257 ResourceManager
   # 3254 Jps
   # 2359 NodeManager
   # 2015 DataNode
   ```

1. Shutdown the Hadoop cluster (including all Hadoop processes)

   ```
   ansible-playbook book/shutdown-hadoop.yaml -vv
   ```

1. Shutdown the zookeeper cluster in a separate step

   ```
   ansible-playbook book/shutdown-zk.yaml -vv
   ```
