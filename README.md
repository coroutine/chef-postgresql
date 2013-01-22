Description
===========
This is a fork of the Opscode PostgreSQL cookbook, which has been modified 
extensively.

* Adds support for PostgresQL 9.1 on Ubuntu 10.04 (Lucid) using a PPA. 
* Adds a recipe to create PostgreSQL user accounts and databases (this 
  particular addition couples this to the `database` cookbook)
* Adds support for configuring Hot Standby with Streaming replication
  (optionally synchronous) in PostgreSQL 9.1

*TODO*: while hot-standby is configured, there's nothing in postgresql that'll 
do automated failover if the master dies.  Typically, that's accomplished by:

* touching a trigger file on the standby (it'll then act as a master)
* using some form of IP failover so the Master's IP address is automatically
  transferred to the standby
* some STONITH mechanism for the old master, so it doesn't come back online

None of the above are handled automatically in this cookbook.

Requirements
============

## Platforms

* Debian, Ubuntu
* Red Hat/CentOS/Scientific (6.0+ required) - "EL6-family"
* Fedora
* SUSE

**Note**: Hot Standby and Streaming replication are only supported on Debian
and Ubuntu.

## Cookboooks

Requires Opscode's `openssl` cookbook for secure password generation, and a C
compiler and development headers in order to build the `pg` RubyGem to provide
Ruby bindings so they're available in other cookbooks.

Opscode's `build-essential` cookbook provides this functionality on
Debian, Ubuntu, and EL6-family.

While not required, Opscode's `database` cookbook contains resources and
providers that can interact with a PostgreSQL database. The Opscode 
`postgresql`cookbook is a dependency of database.

Attributes
==========

The following attributes are set based on the platform, see the
`attributes/default.rb` file for default values.

* `node['postgresql']['version']` - version of postgresql to manage
* `node['postgresql']['dir']` - home directory of where postgresql
  data and configuration lives.
* `node['postgresql']['client']['packages']` - An array of package names
  that should be installed on "client" systems.
* `node['postgresql']['server']['packages']` - An array of package names
  that should be installed on "server" systems.

The following attributes are generated in
`recipe[postgresql::server]`.

* `node['postgresql']['password']['postgres']` - randomly generated
  password by the `openssl` cookbook's library.
* `node['postgresql']['ssl']` - whether to enable SSL (off for version
  8.3, true for 8.4 and later).
* For SSL keys to be automatically generated for you, you need to override `node[:postgresql][:ssl_password]` (only tested on Ubuntu). This password is the passphrase used for signing the certificates.

The following attributes are used by the `setup` recipe:
* `node['postgresql']['databag']` - the data bag in which the `setup` recipe
  searches for items. Default is `postgresql`
* `node['postgresql']['setup_items']` - a list of data bag items 
  containing user/database information. See the notes for the `setup` recipe
  for the expected format.

There are also a number of other attributes defined that control  things such
as host based access (`pg_hba.conf`) and hot standby. A few are listed below,
but see `attributes/default.rb` for more information.
* `node['postgresql']['hba']` - a list of `address`/`method` hashes
  defining the ip address that will be able to connect to PostreSQL

Streaming Replication
---------------------

The following attributes can be modified to enable and configure streaming 
replication and for a Master or Standby.

* `default[:postgresql][:listen_addresses]`
* `default[:postgresql][:master]` - Whether a node is a master. Defaults to 
  false. In this case, replication will not be configured, and the rest of the 
  master settings will be ignored.
* `default[:postgresql][:standby]` - Whether a node is a standby. Defaults to 
  false. In this case, replication will not be configured, and the rest of the 
  standby settings will be ignored.

### Master Server

* `default[:postgresql][:wal_level]` - set to `hot_standby` to enable Hot standby.
* `default[:postgresql][:max_wal_senders]`
* `default[:postgresql][:wal_sender_delay]`
* `default[:postgresql][:wal_keep_segments]`
* `default[:postgresql][:vacuum_defer_cleanup_age]`
* `default[:postgresql][:replication_timeout]`
* `default[:postgresql][:synchronous_standby_names]` - If you want synchronous 
  replication, this must be a string containing a comma-separated list of node 
  names of the standby servers.
* `default[:postgresql][:standby_ips]` - A list of IP addresses for standbys. 
  These MUST be specified in a role.


### Standby Servers

* `default[:postgresql][:master_ip]` - This MUST Be specified in the role. It 
  lets the standby know how to connect to the master.
* `default[:postgresql][:hot_standby]` - set to `on` to enable hot standby.
* `default[:postgresql][:max_standby_archive_delay]`
* `default[:postgresql][:max_standby_streaming_delay]`
* `default[:postgresql][:wal_receiver_status_interval]`
* `default[:postgresql][:hot_standby_feedback]`

Recipes
=======

default
-------

This recipe just includes the `postgresql::client` recipe, which installs the
postgresql client package and required dependencies.

apt_postgresql_ppa
------------------
Adds sources for a PosgresSQL 9.1 package for _Ubuntu 10.04_. **NOTE** that this
recipe should only be used in Ubuntu 10.04. Newer versions of Ubuntu include
PostgreSQL 9.1 in their package repository.

To use this, you'll need to specify the PostgreSQL `version` and `dir` 
attributes. For example, add the folloing to your role:

    override_attributes(
      :postgresql => {
        :version => "9.1",
        :dir => "/etc/postgresql/9.1/main"  
      }
    ) 

client
------

Installs postgresql client packages and development headers during the
compile phase. 

ruby
----

**NOTE** This recipe may not currently work when installing Chef with
  the
  ["Omnibus" full stack installer](http://opscode.com/chef/install) on
  some platforms due to an incompatibility with OpenSSL. See
  [COOK-1406](http://tickets.opscode.com/browse/COOK-1406)

Install the `pg` gem under Chef's Ruby environment so it can be used
in other recipes.

server
------

Includes the `server_debian` or `server_redhat` recipe to get the appropriate
server packages installed and service managed. Also manages the configuration
for the server:

* generates a strong default password (via `openssl`) for `postgres`
* sets the password for postgres
* manages the `pg_hba.conf` file.

server\_debian
--------------

Installs the postgresql server packages, manages the postgresql service and
the postgresql.conf file.

server\_redhat
--------------

Manages the postgres user and group (with UID/GID 26, per RHEL package
conventions), installs the postgresql server packages, initializes the
database and manages the postgresql service, and manages the
postgresql.conf file.

setup
-----
Creates Roles (user account) and Databases from a data bag. See the *Usage*
section for more info.


Resources/Providers
===================

See the [database](http://community.opscode.com/cookbooks/database)
for resources and providers that can be used for managing PostgreSQL
users and databases.

Usage
=====

On systems that need to connect to a PostgreSQL database, add to a run list
`recipe[postgresql]` or `recipe[postgresql::client]`.

On systems that should be PostgreSQL servers, use `recipe[postgresql::server]`
in a run list. This recipe does set a password and expect to use it. It
performs a node.save when Chef is not running in `solo` mode. If you're using
`chef-solo`, you'll need to set the attribute 
`node['postgresql']['password']['postgres']` in your node's `json_attribs` file
or in a role.

Streaming Replication/Hot Standby
---------------------------------
To set this up, you'd need to:

1. Bootstrap the Nodes (you've got know know their IP addresses!)
2. Assign the `server` recipe to the master and slave nodes to install a
   standard postgresql server.
3. Log into the Standby machine and shut down PostgreSQL.
4. Create the Master/Standby Roles (see below) and apply to each node.
        * Make sure both nodes have access to each others' PostgreSQL service
          by adding the appropriate values for the `node['postgresql']['hba']`
          attribute.
5. Run `chef-client` on the Master. Wait for it to finish.
6. Run `chef-client` on the Standby. It will fail. That's ok. Log into the
   standby and make sure PostgreSQL is not running.
7. Log into the master and manually remove 
   `/var/lib/postgresql/9.1/main/.initial_transfer_complete`, then re-run
   `chef-client` (it will again copy the database data directory 
   over to the standby via rsync, so you'll be prompted for a password unless 
   you've got public keys in place... make sure this step works!)
8. Restart postgresql on the master, then on the standby and run `chef-client`
   on both nodes. Check to make sure PostgreSQL's `sender` and `receiver`
   processes are running:
    * Run `ps -ef | grep sender` on the Master
    * Run `ps -ef | grep receiver` on the Standby
9. Subsequent runs of `chef-client` should work without any errors.

### Master Role
To configure a Master server, you would need to create a role that sets the 
appropriate properties. For example, given that you have a node namded `db2` 
with an ip address of `10.0.0.11`, you might create a role similar to the one 
below:

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
        :standby_ips => [ "10.0.0.11", ],
        :synchronous_standby_names => ["db2", ], # Omit this if you don't want
                                                 # synchronous replication
        :hba => [
            { :method => 'md5', :address => '127.0.0.1/32' },
            { :method => 'md5', :address => '::1/128' },
            { :method => 'md5', :address => '10.0.0.10' },
            { :method => 'md5', :address => '10.0.0.11' },
        ]
      }
    )

### Standby Role
To configure a Standby, you could create a similar role. Assuming the master 
was available at an ip address of `10.0.0.10`:

    name "pg_server_standby"
    description "A PostgreSQL Standby"
    run_list "recipe[postgresql::server]"

    override_attributes(
      :postgresql => {
        :version => "9.1",
        :dir => "/etc/postgresql/9.1/main",
        :standby => true,
        :hot_standby => "on",
        :master_ip => "10.0.0.10",
        :hba => [
            { :method => 'md5', :address => '127.0.0.1/32' },
            { :method => 'md5', :address => '::1/128' },
            { :method => 'md5', :address => '10.0.0.10' },
            { :method => 'md5', :address => '10.0.0.11' },
        ]
      }
    )

### User/Database Setup

To configure users and databases, create a data bag with the name used in the
`default[:postgresql][:databag]` attribute. Items in this databag will be used
to create both PostgreSQL users and databases. The format of each databag item
should be similar to the following:

    {
       "id": "sample_db_setup",
       "users": [
           {
               "username":"some_user",
               "password":"some_password",
               "superuser": "true",
           }
       ],
       "databases": [
           {
               "name":"some_db",
               "owner":"some_user", 
               "template":"template0",
               "encoding": "UTF8",
               "locale": "en_US.utf8"
           }
       ] 
    }


Then, override the `node['postgresql']['setup_items']` attribute in a role:

    override_attributes(
      :postgresql => {
        :databag     => "postgresql", # databag from which items are fetched
        :setup_items => ["sample_db_setup", ]  # name of item from which
                                               # user/database info is read.
      }
    )

License and Author
==================

Author:: Joshua Timberman (<joshua@opscode.com>)
Author:: Lamont Granquist (<lamont@opscode.com>)
Author:: Brad Montgomery (<brad@bradmontgomery.net>)

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
