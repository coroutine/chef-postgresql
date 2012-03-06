#
# Cookbook Name:: coroutine_clients
# Recipe::apt_postgresq91_ppa
#
# Copyright 2012, Coroutine
#
# All rights reserved.
#
# Add the PostgreSQL 9.1 sources for Ubuntu
# using the PPA available at:
# https://launchpad.net/~pitti/+archive/postgresql

# NOTE: "recipe[apt]" must be included somewhere... 
# this is included by default in our base role.

case node["platform"]
when "ubuntu"
  apt_repository "postgresql" do
    uri "http://ppa.launchpad.net/pitti/postgresql/ubuntu"
    distribution node['lsb']['codename']
    components ["main"]
    keyserver "keyserver.ubuntu.com"
    key "8683D8A2"
    action :add
    notifies :run, resources(:execute => "apt-get update"), :immediately
  end
end
