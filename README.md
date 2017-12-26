# Vault Playground V2.0.0

This repo is meant to make it easier for developers, operators, and CI servers to work locally with a production-like Vault environment.
The Makefile contained in this repository will allow users to spin up (by default) a Consul cluster with 3 nodes, and 2 Vault servers running
in HA mode. It also provides helpers for snapshotting the state of the cluster and restoring it from a cached or passed in Consul snapshot.
By overriding the default values for task environment variables you can also snapshot and restore to or from remote Vault clusters. 
This is meant for convenience during development only; it's still considered a bad practice to automate the unsealing of a production Vault cluster.

## Use Cases

While it's possible to run an ad-hoc in memory Vault container in Docker, doing continued development against it is cumbersome and collaboration 
with others can be clunky. Further, dev-mode Vault or Vault backed by the filesystem isn't a good mirror for most production environments (hopefully). If you're someone
who needs a place to test failover scenarios, application resiliency, break glass procedures, or automation tooling, Vault Playground is meant to simplify 
your life.

### Application Development
Besides letting developers test what would happen in the event of a partial or complete outage of Vault/Consul, Vault Playground also makes it possible for 
developers to run their applications against a local Vault instance that is seeded with relevant local secrets. Because the data inside a Consul snapshot is
encrypted, snapshot files could be committed into source control. The keys needed to unseal the Vault would still need to be passed out of band if the snapshot 
contained any sensitive data. If it didn't then the initialization file could be committed as well. _This feature is meant to help with local secrets only, 
it's still a bad idea to commit real secrets into source control EVEN WHEN THEY'RE ENCRYPTED._

### Failover Scenarios
If you're an operator that's new to Vault and Consul you can use the Vault Playground to test various data center failure models and practice manual restoration.

### Breakglass Procedures
If you're an operator or a developer you're probably interested to know what would happen in the event of a credential leak. By restoring a snapshot or otherwise seeding
Vault with known data you can test partial revocations of secrets, tokens, and leases, or find out how applications would handle a total seal event.

### Automation Tooling
If you're an operator or developer writing tests for your infrastructure tooling it's helpful to run them against a realistic environment. The Vault Playground can be 
deployed onto a CI server and used to restore known states and run tests while also making it quick and easy to burn everything down and create a brand new environment
for each batch of tests.

## Prerequisites
  - [Docker](https://www.docker.com/get-docker) - This uses Docker to run Vault and Consul in containers
  - Network access to the [Docker Hub](https://hub.docker.com/) - On first init this calls out to get official versions of [Consul](https://hub.docker.com/_/consul/) and [Vault](https://hub.docker.com/_/vault/) if Docker doesn't have them cached locally.
  - [curl](https://curl.haxx.se/) A command line tool for making network requests, usually installed on most systems by default.
  - [jq](https://stedolan.github.io/jq/) A lightweight command line tool for parsing JSON. Available on most systems and easy to install on others.
  
## Getting Started

1. Clone this repo to the directory of your choice
1. Run `make init` to setup your environment
1. Run `make help` to see other available commands:

```text
help                           Displays information about available make tasks
init                           Spin up local Docker instances for all dependencies on a dedicated Docker network
destroy                        Destroy local Docker instances and their Docker network
snapshot                       Backup the state of Vault by taking a snapshot of Consul and storing it in the local cache
purge                          Delete the local cache of snapshots and initialization keys
restore                        Restore previous Vault state by restoring a Consul snapshot
creds                          Shows the root token and unseal keys for the currently running Vault instance cached
status                         Displays the current state of the Vault Playground network in Docker.
vault-leader                   Displays the address of the current Vault leader
```

## Talking To Vault

This tool is meant to be run locally and make it easier to test and debug Vault workflows, so it _does not_ enable TLS. As a result
you'll have to explicitly tell the Vault CLI to connect over HTTP. Fortunately, Vault supports the `VAULT_ADDR` environment variable. 
If you're using `docker exec` this environment variable has already been set inside the Vault instances.

```bash
docker exec vp-vault1 vault status
```

Locally, you can export it:

```bash
export VAULT_ADDR=$(make vault-leader)
```
 
and use Vault as you normally would:
 
```bash
vault status
```

## The Tasks

Make was used to provide a simple and portable interface, but all of the tasks in this repo have been written as (mostly) 
self contained shell scripts that could be run independently of Make. The only interdependency between these scripts is 
that restore will call init if it detects that it's pointed at a local Consul server. Many of the tasks can have their 
behavior altered by environment variables.

### init

**Environment**
  - `VP_NAMESPACE` (vp) This is the name of the Docker network that will be created. This string will also prefix all container names. Essentially this is a namespace for Vault Playground.
  - `VP_AUTO_INIT` (true) If true, after launching Vault the script will also run init, cache the resulting keys, and automatically unseal Vault
  - `VP_VAULT_CLUSTER_SIZE` (2) The script will launch this many Vault nodes clustered in HA mode.
  - `VP_CONSUL_CLUSTER_SIZE` (3) How many Consul servers do you need?
  
This script creates a dedicated docker network (called `vp`) and spins up the configured number of Vault and Consul servers. 
By default this also initializes and unseals Vault automatically so you can use it immediately. When the script completes
it will output the addresses where Consul and Vault can be reached locally:

```text
Consul is now running at: http://127.0.0.1:32845
Vault is now running at: http://127.0.0.1:32849 set your host's VAULT_ADDR environment variable to communicate directly with it using the Vault CLI.
```

If `VP_AUTO_INIT` is true, the script will cache the output of the initialize API call locally (`$HOME/.vault-playground/init_dumps`) in a file 
named after the Docker ID of the main vault server. 

### snapshot

**Environment**
  - `VP_NAMESPACE` (vp) This is the name of the Docker network any local containers are running on.
  - `VP_SNAPSHOT_NAME` (timestamp of the form: `%Y-%m-%d-%H-%M-%S`) Snapshots are named using the ID of the active Vault instance concatenated with this value. 
  - `VP_CONSUL_TARGET` - (The Vault Playground Consul node) The Consul server that should be snapshotted
  - `VP_CONSUL_DATACENTER` - (dc1) The Consul data center that should be snapshotted, locally this will almost always be the default. 
  
This script creates a snapshot in the local cache (`$HOME/.vault-playground/snapshots`) that by default is named with a timestamp.
Generate a custom named snapshot with an environment variable: `VP_SNAPSHOT_NAME=the-one-with-postgres-secrets make snapshot`

In addition to snapshotting the local Docker Cluster, you can also point this script at a running external Consul server 
to pull down and cache a local snapshot:

```
VP_CONSUL_TARGET=https://myconsul.biz:8500 VP_SNAPSHOT_NAME=myconsul-biz-12-31-2017 make snapshot
```

### restore

**Environment**
  - `VP_NAMESPACE` (vp) This is the name of the Docker network any local containers are running on.
  - `VP_SNAPSHOT` (empty string) Path to the Consul snapshot to restore. If this is blank, restore will list all the snapshots in its cache (`$HOME/.vault-playground/snapshots`).
  - `VP_INIT_DUMP` (empty string) Path to a file containing the output of the Vault initialization command. If this file doesn't exist, restore will check it's cache (`$HOME/.vault-playground/init_dumps`) if it finds nothing it will still restore the snapshot, but leave Vault sealed.
  - `VP_CONSUL_TARGET` - (The Vault Playground Consul node) The Consul server that the snapshot should be restored to
  - `VP_VAULT_TARGETS` - (all running Vault Playground Vault containers) A space delimited list of Vault servers that should be contacted for unsealing if an init dump file was provided or existed in the cache.

**Dependencies**
  - `init` If the `VP_CONSUL_TARGET` variable has not been overridden this script calls out to init, setting `VP_AUTO_INIT=false` so it can setup a clean cluster before running the restore.
  
Unless a snapshot file is specified this script will list all snapshots in its cache and prompt the user to select one. 
Once the snapshot is restored the script will attempt to locate a valid initialization dump file in its cache if one was 
not passed in. If it is able to find one it will attempt to automatically unseal Vault. If it is unable to do so it will
notify the user who would have to manually unseal the Vault instances. Even if the Vault is not able to be unsealed the 
snapshot will still be restored. 

### creds

**Environment**

  - `VP_NAMESPACE` (vp) This is the name of the Docker network any local containers are running on.

This is a helper task that looks in the cache for any initialization dumps from the currently running Vault instance and
outputs them to the screen, allowing the user to see both the root and unseal keys for the currently running Vault.

### destroy

**Environment**

  - `VP_NAMESPACE` (vp) This is the name of the Docker network any local containers are running on.

This script terminates and removes all containers deployed in the Vault Playground docker network (`vp`).

### vault-leader

**Environment**

  - `VP_NAMESPACE` (vp) This is the name of the Docker network any local containers are running on.


This script outputs the current leader and the port it's exporting on the host. Useful for setting the VAULT_ADDR 
environment variable:

```bash
export VAULT_ADDR=$(make vault-leader)
```

### purge

This script deletes all cached credentials and snapshots by removing the `$HOME/.vault-playground` directory.

## Contributing

Pull requests welcome, especially if they help provide test coverage for the task scripts.
