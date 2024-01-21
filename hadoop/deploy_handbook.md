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

1. configure passwordless ssh access\
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

1. Initialize the cluster environment by setting up the keys and install Hadoop manifests.

    - Execute `ansible-playbook book/sync-host.yaml` and enter sudo password of controlled machines. The password needs
      to be same on each machine.
        - **Hint**: add `-vvv` argument at the end of the `ansible-playbook` command can help you debug issue.(The
          number of 'v' stands for verbosity)
    - Execute `ansible-playbook book/install-hadoop.yaml`
        - Note: if download artifact from remote repo, it could take up to 10min.
    - Clear the machines under the `[newborn]` section after hadoop installation completes.

1. Configure and launch zookeeper

    - Make sure `[zk_nodes]` contains all nodes to install zookeeper, and has `ansible_host`, `myid` correctly
      configured.
    - Look JVM args in `book/config-zk.yaml` and change if needed.
        - **Note**: Understand what existing argument means first.
    - Execute `ansible-playbook book/config-zk.yaml`

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
    - Execute `ansible-playbook book/config-hadoop.yaml`
        - Note: Native compression test would fail since some files are not configured yet. This shouldn't affect Hadoop
          initialization though.

