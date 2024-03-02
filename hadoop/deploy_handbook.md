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
     with real key:\
     **Note**: you can
     use [ssh-copy-id](https://www.digitalocean.com/community/tutorials/ssh-essentials-working-with-ssh-servers-clients-and-keys#copying-your-public-ssh-key-to-a-server-with-ssh-copy-id)
     instead if you have password access to other VMs.
     This guide assume you already have root access, and the public key is copied to the root directory of each
     controlled machine.
     Configure your accessibility first if needed.
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
       Hostname 192.168.62.141
       User admin
       PreferredAuthentications publickey
       IdentityFile ~/.ssh/<keyname>
     ```

1. Setup ansible environment

   Note: there are two ways to do this, directly do this on ansible control node, or use ansible docker container.

   But first, change directory to the ansible project(the location of this .md file) and configure the `hosts` ansible
   file.

   **Option 1** Docker

    1. Change directory to ansible project hadoop directory `ansible-script/hadoop` (the location of this .md file) on
       the host machine.\
       **Note**: If this is the first time running the setup script on the ansible control node, check
       the `sync host failure`
       section under the `troubleshoot` section and update the `/etc/hosts` first.
    1. Enter the docker container ansible using the "jwhuang42/ansible:8.7.0" image, mount related volumes
       ```
       docker run -it --rm --name ansible -v "$PWD":/work -v "$HOME/.ssh":"/root/.ssh" -v /etc/hosts:/etc/hosts jwhuang42/ansible:8.7.0
       ```
    1. Inside the container
       ```
       # Go to work directory and change owner from 1000 to root
       cd /work && chown root:root ~/.ssh/config && chmod +x deploy-all.sh && chmod +x deploy-ozone-all.sh
       ```
    1. Check and configure the ansible hosts file.
    - Change the VM IP addresses to the real one for Hadoop deployment under the `[nodes]` and `[zk_nodes]` section.
    - Add the IPs of the VMs you intend to install Hadoop under the `[newborn]` section.
   - Update the `ansible_ssh_private_key_file` under the `[hadoop_nodes]` section (points to the same IdentityFile in
     the .ssh/config).

   **Option 2** Local Machine

    1. Makes sure python 3.10 and ansible 8.7.0 are installed before proceed. You can check the `Dockerfile` in the
       parent
       directory for the installation guide.

    2. Change directory to ansible project hadoop directory `ansible-script/hadoop` (the location of this .md file) on
       the host machine.

## One line Deployment

You can execute the single command `./deploy-all.sh` under the working directory to directly set up a hadoop HA cluster.

The entire process may take around 30-45 min if you download the files online.
Use local repo could accelerate the speed
(Check vars in `book/install-hadoop.yaml` on where to put the downloaded binaries locally).

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

## Troubleshoot

### sync host failure

If this is your first time deploy cluster, and you don't have any hosts mapping configured in the `/etc/hosts` folder of
your ansible control node, you may experience the following error when `sync-host.yaml` playbook is executed:

```
[Errno 16] Device or resource busy: b'/etc/.ansible_<hash_value>' -> b'/etc/hosts'
```

This happens because docker daemon manages the `/etc/hosts` file once a container starts, you can not modify it within
the container.
The walk around is to copy the `[nodes]` section in the hosts file in the current directory to the `/etc/hosts`
on the ansible control node first, and perform the workflow after that. For example, copy:

```
# BEGIN ANSIBLE MANAGED HOSTNAME
192.168.62.141 my.hadoop1 my.hbase1 my.ozone1 my.zk1
192.168.62.142 my.hadoop2 my.hbase2 my.ozone2 my.zk2
192.168.62.143 my.hadoop3 my.hbase3 my.ozone3 my.zk3
192.168.62.144 my.hadoop4 my.hbase4 my.ozone4
# END ANSIBLE MANAGED HOSTNAME
```

into the `/etc/hosts` on the ansible control machine before executing the `sync-host.yaml` playbook.