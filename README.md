Description
===========

TODO: while hot-standby is configured, there's nothing in postgresql that'll do automated failover if the 
master dies.  Typically, that's accomplished by:

    * touching a trigger file on the standby (it'll then act as a master)
    * using some form of IP failover so the Master's IP address is automatically transferred to the standby
    * some STONITH mechanism for the old master, so it doesn't come back online

This is a fork of the Opscode PostgreSQL cookbook, which as been modified extensively:
    * supports PostgresQL 9.1 on ubuntu (10.04) (not tested on Red Hat platforms).
    * adds a recipe to create PostgreSQL user accounts and databases (this particular addition couples this to the `database` cookbook)

Additionally, the server recipe supports configuration for Hot Standby with Streaming replication (optionally synchronous). For more information, see the *Attributes* and *Usage* sections below. **NOTE** that this **only** works with PostgreSQL 1.9.

Requirements
============

## Platforms

* Debian, Ubuntu
* Red Hat/CentOS/Scientific (6.0+ required) - "EL6-family"
* Fedora
* SUSE

Tested on:

* Ubuntu 10.04, 11.10
* Red Hat 6.1, Scientific 6.1

## Cookboooks

Requires Opscode's `openssl` cookbook for secure password generation.

Requires a C compiler and development headers in order to build the
`pg` RubyGem to provide Ruby bindings so they're available in other
cookbooks.

Opscode's `build-essential` cookbook provides this functionality on
Debian, Ubuntu, and EL6-family.

While not required, Opscode's `database` cookbook contains resources
and providers that can interact with a PostgreSQL database. This
cookbook is a dependency of that one.

Attributes
==========

The following attributes are set based on the platform, see the
`attributes/default.rb` file for default values.

* `node['postgresql']['version']` - version of postgresql to manage
* `node['postgresql']['dir']` - home directory of where postgresql
  data and configuration lives.

The following attributes are generated in
`recipe[postgresql::server]`.

* `node['postgresql']['password']['postgres']` - randomly generated
  password by the `openssl` cookbook's library.
* `node['postgresql']['ssl']` - whether to enable SSL (off for version
  8.3, true for 8.4).

The following attribute is used by the `setup` recipe:
* `node['postgresql']['setup_items']` - a list of data bag items 
  containing user/database information 

Streaming Replication
---------------------

The following attributes can be modified to enable and configure streaming replication and for a Master or Standby.

* `default[:postgresql][:listen_addresses]`
* `default[:postgresql][:master]` - Whether a node is a master. Defaults to false. In this case, replication will not be configured, and the rest of the master settings will be ignored.
* `default[:postgresql][:standby]` - Whether a node is a standby. Defaults to false. In this case, replication will not be configured, and the rest of the standby settings will be ignored.

### Master Server

* `default[:postgresql][:wal_level]` - set to `hot_standby` to enable Hot standby.
* `default[:postgresql][:max_wal_senders]`
* `default[:postgresql][:wal_sender_delay]`
* `default[:postgresql][:wal_keep_segments]`
* `default[:postgresql][:vacuum_defer_cleanup_age]`
* `default[:postgresql][:replication_timeout]`
* `default[:postgresql][:synchronous_standby_names]` - If you want synchronous replication, this must be a string containing a comma-separated list of node names of the standby servers.
* `default[:postgresql][:standby_ips]` - A list of IP addresses for standbys. These MUST be specified in a role.


### Standby Servers

* `default[:postgresql][:master_ip]` - This MUST Be specified in the role. It lets the standby know how to connect to the master.
* `default[:postgresql][:hot_standby]` - set to `on` to enable hot standby.
* `default[:postgresql][:max_standby_archive_delay]`
* `default[:postgresql][:max_standby_streaming_delay]`
* `default[:postgresql][:wal_receiver_status_interval]`
* `default[:postgresql][:hot_standby_feedback]`

Recipes
=======

default
-------

Includes the client recipe.

apt_postgresql_ppa
------------------
Adds sources for a PosgresSQL 9.1 package for Ubuntu 10.04. You'll need to specify the PostgreSQL `version` and `dir` attributes. For example, add the folloing to your role:

    override_attributes(
      :postgresql => {
        :version => "9.1",
        :dir => "/etc/postgresql/9.1/main"  
      }
    ) 

client
------

Installs postgresql client packages and development headers during the
compile phase. Also installs the `pg` Ruby gem during the compile
phase so it can be made available for the `database` cookbook's
resources, providers and libraries.

server
------

Includes the `server_debian` or `server_redhat` recipe to get the
appropriate server packages installed and service managed. Also
manages the configuration for the server:

* generates a strong default password (via `openssl`) for `postgres`
* sets the password for postgres
* manages the `pg_hba.conf` file.

server\_debian
--------------

Installs the postgresql server packages, manages the postgresql
service and the postgresql.conf file.

server\_redhat
--------------

Manages the postgres user and group (with UID/GID 26, per RHEL package
conventions), installs the postgresql server packages, initializes the
database and manages the postgresql service, and manages the
postgresql.conf file.

setup
-----
Creates Roles (user account) and Databases from a data bag. Note that the postgres user's password is automatically created by the `server` recipe and can be referenced in `node['postgresql']['password']['postgres']`.

Resources/Providers
===================

See the [database](http://community.opscode.com/cookbooks/database)
for resources and providers that can be used for managing PostgreSQL
users and databases.

Usage
=====

On systems that need to connect to a PostgreSQL database, add to a run
list `recipe[postgresql]` or `recipe[postgresql::client]`.

This does install the `pg` RubyGem, which has native C extensions, so
that the resources and providers can be used in the `database`
cookbook, or elsewhere in the same Chef run. Use Opscode's
`build-essential` cookbook to make sure the proper build tools are
installed so the C extensions can be compiled.

On systems that should be PostgreSQL servers, use
`recipe[postgresql::server]` on a run list. This recipe does set a
password and expect to use it. It performs a node.save when Chef is
not running in `solo` mode. If you're using `chef-solo`, you'll need
to set the attribute `node['postgresql']['password']['postgres']` in
your node's `json_attribs` file or in a role.

Streaming Replication/Hot Standby
---------------------------------
To set this up, you'd need to:

1. Bootstrap the Nodes (you've got know know their IP addresses!)
2. Run the recipe to install a standard postgresql server on both machines.
3. Log into the Standby machine and shut down postgresql.
4. Set up Master/Standby Roles (see below) 
5. Assign the roles to the appropriate Nodes
6. Run `chef-client` on the Master (it will copy the database data directory over to the standby via rsync, so you'll be prompted for a password)
    * TODO: this breaks down here...
    * run chef-client on the master
    * run chef-client on the standby
    * kill postgresql on the standby
    * On the standby: manually remove everything in `/var/lib/postgresql/9.1/main` except for `pg_xlog` and `recovery.conf`
    * On the master: manually remove `/var/lib/postgresql/9.1/main/.initial_transfer_complete`, then re-run `chef-client`
    * run chef-client on the master, (making sure the the rsync command works)
    * restart postgresql on the master, then on the standby
    * On the master, run `ps -ef | grep sender` and then `ps -ef | grep receiver` on the slave
    * NOW, running `chef-client` on both nodes should work without any errors.
    * It'd be nice if this was all handled by chef :(

### Master Role
To configure a Master server, you would need to create a role that sets the appropriate properties. For example, given that you have a node namded `db2` with an ip address of `10.0.0.2`, you might create a role similar to the one below:

    name "pg_server_master"
    description "A PostgreSQL Master"
    run_list "recipe[postgresql::server]"

    override_attributes(
      :postgresql => {
        :version => "9.1",
        :dir => "/etc/postgresql/9.1/main",
        :master => true,
        :listen_addresses => "*",
        :wal_level => "hot_standby",
        :max_wal_senders => 5,
        :standby_ips => [ "10.0.0.2", ],
        :synchronous_standby_names => ["db2", ] # Omit this if you don't want synchronous replication
      }
    )

### Standby Role
To configure a Standby, you could create a similar role. Assuming the master was available at an ip address of `10.0.0.1`:

    name "pg_server_standby"
    description "A PostgreSQL Standby"
    run_list "recipe[postgresql::server]"

    override_attributes(
      :postgresql => {
        :version => "9.1",
        :dir => "/etc/postgresql/9.1/main",
        :standby => true,
        :hot_standby => "on",
        :master_ip => "10.0.0.1"
      }
    )

### User/Database Setup

To configure users and databases, create a `postgresql` data bag, and add items that look similar to the following:

    {
        "id": "sample",
        "users": [
            {
                "username":"sample_username",
                "password":"sample_password"
            }
        ],
        "databases": [
            {
                "name":"sampledb",
                "owner":"sample_username", 
                "template":"template0",
                "encoding": "utf8"
            }
        ] 
    }

The, override the `node['postgresql']['setup_items']` in a role:

    override_attributes(
      :postgresql => {
        :setup_items => ["sample", ]  # name of the data bags from which
                                      # user/database info is read.
      }
    )


Changes/Roadmap
==============

## TODO: include changes added to this repo

## v0.99.2:

* [COOK-916] - use < (with float) for version comparison.

## v0.99.0:

* Better support for Red Hat-family platforms
* Integration with database cookbook
* Make sure the postgres role is updated with a (secure) password

License and Author
==================

Author:: Joshua Timberman (<joshua@opscode.com>)
Author:: Lamont Granquist (<lamont@opscode.com>)

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
