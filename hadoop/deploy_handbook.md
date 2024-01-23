## Prerequisite

1. Prepare Ubuntu 22.04 for all VMs, and make sure ssh server is installed and enabled on all related machines

   **Suggestion**: You may want to take a snapshot of each VM at this stage, so you can rollback the state and reinstall
   everything if needed.

1. Install python on the control machine

    - On the control machine, make sure python 3.10
      is [installed](https://phoenixnap.com/kb/how-to-install-python-3-ubuntu)(follow method 3)
    - Point "python" command to the python3.10 binary using `sudo apt install python-is-python3`.

1. Install Ansible

    - From your control node, run the following command to include the official project’s PPA (personal package archive)
      in your system’s list of sources: `sudo apt-add-repository ppa:ansible/ansible`
    - Next, refresh your system’s package index so that it is aware of the packages available in the newly included
      PPA: `sudo apt update`
    - Following this update, you can install the Ansible software with:
      `sudo apt install ansible`
    - The ansible core module is version 2.15 at Jan 20 2024, you can check the latest version
      using `ansible --version`.

1. change directory to the ansible project(the location of this .md file) and configure the `hosts` ansible file

    - Change the VM IP addresses to the real one for Hadoop deployment under the `[nodes]` and `[zk_nodes]` section.
    - Add the IPs of the VMs you intend to install Hadoop under the `[newborn]` section.
    - Change the `ansible_user` to proper user in `[all:vars]`(you can use the default `admin` user, but you may need to
      create it first).
      Check [this post](https://www.digitalocean.com/community/tutorials/how-to-add-and-delete-users-on-ubuntu-20-04)
      how to create a new user.
    - make sure the `ansible_user` is in `sudo` group. On each node run: `sudo usermod -aG sudo <ansible_user>`
    - Set passwordless access for the `ansible_user` on each node. For each node:
        - Create a file at `/etc/sudoers.d/<ansible_user>` and add the following line:
      ```
      <ansible_user> ALL=(ALL:ALL) NOPASSWD:ALL
      ```

1. Make sure you are familiar with
   the [ssh concepts](https://www.digitalocean.com/community/tutorials/ssh-essentials-working-with-ssh-servers-clients-and-keys).

1. set ssh key based authentication\
   **Note**: The assumption is the control machine can ssh to all controlled machine via password, if passwordless
   access is already configured,\
   just make sure strict ssh host checking on each controlled machine is disabled.

    - change directory `cd ~/.ssh`.
    - on ansible control machine, run `ssh-keygen -t rsa -b 4096` to generate ssh key pair(without passphrase).
    - Check the generated public key: `cat ~/.ssh/id_rsa.pub` (replace `id_rsa.pub` with the actual pub key name if
      needed)
    - On each ansible controlled machine (i.e. ansible host), run the following command, replace the `<pub_key_string>`
      with real key:
      ```
      cat <<EOF >> ~/.ssh/authorized_keys
      ssh-rsa <public_key_content>
      EOF
      ```
    - Disable strict ssh host checking on each controlled machine:
        1. `sudo vim /etc/ssh/ssh_config`.
        2. Under the `Host *` section, uncomment the `StrictHostKeyChecking` line and replace
           with `StrictHostKeyChecking no`.
    - If your key name or username is different from the default one (i.e. key name is not `id_rsa`
      or the user on the control machine and the controlled machines are different), you may need to configure ssh
      client on the control machine via a file at `~/.ssh/config` to access the controlled machines.
      Check [this link](https://www.digitalocean.com/community/tutorials/how-to-configure-custom-connection-options-for-your-ssh-client)
      for more detail.
      A sample config on one of the nodes could look like:
      ```
      Host hadoop01
        Hostname <node_hostname> # may need to configure /etc/hosts first
        User admin
        IdentityFile ~/.ssh/my_custom_privatekey1
      ```
    - Change directory back to the `ansible-script/hadoop`(the location of this .md file)

## Cluster Configuration, Zookeeper set up, and Hadoop Installation
1. Initialize the cluster environment by setting up the keys and install Hadoop manifests.

   - Execute `ansible-playbook book/sync-host.yaml -vv` and enter sudo password of controlled machines. The password
     needs
      to be same on each machine.
        - **Hint**: add `-vvv` argument at the end of the `ansible-playbook` command can help you debug issue.(The
          number of 'v' stands for verbosity, 'vvv' has the highest verbosity)
   - Execute `ansible-playbook book/install-hadoop.yaml -vv`
        - Note: if download artifact from remote repo, it could take up to 10min.
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
        - Note: Native compression test would fail since some files are not configured yet. This shouldn't affect Hadoop
          initialization though.

## Hadoop Initialization

**Note**: Below is the step-by-step guide on how to start a Hadoop HA cluster. If the verification fail at any step,
find if there is a configuration issue in the previous steps.

At any time some processes have problem starting on some nodes, or you'd like to try again, delete everything inside
the `/data/hadoop` directory on each node
and restart everything from `Hadoop Initialization` section (i.e. treat this initialization guide as a "transaction").

If everything works fine (i.e. vm config, network config, ssh config, user config) and you are unable to locate the bug,
capture the full error/log message and report the issue.

1. Verify the `QuorumPeerMain` process on each `[zk_nodes]` has started.

   ```
   ansible zk_nodes -m shell -a '. /etc/profile && jps | grep QuorumPeerMain'
   
   # Confirm there is one and only one leader, and the version matches what's specified in `book/install-hadoop.yaml`
   ansible zk_nodes -m shell -a '. /etc/profile && /opt/zookeeper/bin/zkServer.sh version && /opt/zookeeper/bin/zkServer.sh status'
   ```

### Start HDFS

1. Start `JournalNode` service on all `[journalnodes]`.

   ```
   ansible journalnodes -m shell -a '. /etc/profile && nohup hdfs --daemon start journalnode'

   # Check if JournalNode process exists on each node specified in hosts-->[journalnodes] section
   ansible journalnodes -m shell -a '. /etc/profile && jps | grep JournalNode'
   ```

1. Format the namenode with id `nn1` and start the process.

   ```
   ansible 'namenodes[0]' -m shell -a '. /etc/profile && hdfs namenode -format'

   ansible 'namenodes[0]' -m shell -a '. /etc/profile && nohup hdfs --daemon start namenode'
   
   # Check if the NameNode process exists on first [namenodes] (i.e. node in hosts-->[namenodes][0])
   ansible 'namenodes[0]' -m shell -a '. /etc/profile && jps | grep NameNode'
   ```

1. For rest of the namenodes, sync the metadata with `nn1` and start the process.

   ```
   ansible 'namenodes[1:]' -m shell -a '. /etc/profile && hdfs namenode -bootstrapStandby'
   
   ansible 'namenodes[1:]' -m shell -a '. /etc/profile && nohup hdfs --daemon start namenode'
   
   # Check if the NameNode process exists on rest of the [namenodes] (i.e. nodes in hosts-->[namenodes][1:])
   ansible 'namenodes[1:]' -m shell -a '. /etc/profile && jps | grep NameNode'
   ```

1. Start the DataNode process on each `hosts-->[datanodes]`

   ```
   ansible datanodes -m shell -a '. /etc/profile && nohup hdfs --daemon start datanode'
   
   # Check if the DataNode process exists on each hosts-->[datanodes] section.
   ansible datanodes -m shell -a '. /etc/profile && jps | grep DataNode'
   ```

1. Check if both namenodes are in the `standby` state. (Can be executed on any namenode)

   ```
   ansible 'namenodes[0]' -m shell -a '. /etc/profile && hdfs haadmin -getServiceState nn1'
   ansible 'namenodes[0]' -m shell -a '. /etc/profile && hdfs haadmin -getServiceState nn2'
   ```

1. Format the state of `DFSZKFailoverController` on zookeeper.

   ```
   ansible 'namenodes[0]' -m shell -a '. /etc/profile && hdfs zkfc -formatZK'
   ```

1. Restart the HDFS cluster.

   ```
   ansible 'namenodes[0]' -m shell -a '. /etc/profile && stop-dfs.sh'
   
   ansible 'namenodes[0]' -m shell -a '. /etc/profile && start-dfs.sh'
   
   # Check if the `DFSZKFailoverController` process exists on each namenode
   ansible 'namenodes' -m shell -a '. /etc/profile && jps | grep FailoverController'
   ```

1. Check if one of the namenodes is in `active` state.

```
ansible 'namenodes[0]' -m shell -a '. /etc/profile && hdfs haadmin -getServiceState nn1'
ansible 'namenodes[0]' -m shell -a '. /etc/profile && hdfs haadmin -getServiceState nn2'
```

### Start YARN

1. Run script and check if ResourceManager and NodeManager processes are properly start.

   ```
   ansible 'namenodes[0]' -m shell -a '. /etc/profile && start-yarn.sh'
   
   # Check if both `ResourceManager` and `NodeManager` exist on specified nodes.
   ansible 'hadoop_nodes' -m shell -a '. /etc/profile && jps | grep Manager'
   ```

1. Check the state of `ResourceManager` and locate the active one (should only have one)

   ```
   ansible 'namenodes[0]' -m shell -a '. /etc/profile && yarn rmadmin -getServiceState rm1'
   
   ansible 'namenodes[0]' -m shell -a '. /etc/profile && yarn rmadmin -getServiceState rm2'
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

## Cluster Shutdown

**Note**: This is probably not needed for production environment, but you may use this during cluster set up test or
upgrade.

The following shutdown guide will close everything starting from a Hadoop cluster with HA YARN and HA HDFS.
you can use a subset of the command to shut down components as needed, just make sure **the commands are executed in the
small to large order**.
Otherwise, the data might be corrupted!

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

1. Shutdown the YARN cluster (Make sure all jobs have completed first before running this)

   ```
   # Remove all `ResourceManager` and `NodeManager` processes
   ansible 'namenodes[0]' -m shell -a '. /etc/profile && stop-yarn.sh'
   ```

1. Shutdown the HDFS cluster

   ```
   # Remove all `NameNode` and `DataNode` processes
   ansible 'namenodes[0]' -m shell -a '. /etc/profile && stop-dfs.sh'
   ```

1. Shutdown the JournalNode processes

   ```
   # Remove all `JournalNode` processes
   ansible journalnodes -m shell -a '. /etc/profile && nohup hdfs --daemon stop journalnode'
   ```

1. Shutdown the zookeeper cluster

   ```
   # Remove all `QuorumPeerMain` processes
   ansible zk_nodes -m shell -a '. /etc/profile && /opt/zookeeper/bin/zkServer.sh stop'
   ```

1. Check all processes are properly closed (jps should be the only left process on each node)

   ```
   ansible 'nodes' -m shell -a '. /etc/profile && jps'
   ```
