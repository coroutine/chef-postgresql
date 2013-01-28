# -*- coding: utf-8 -*-
#
# Cookbook Name:: postgresql
# Recipe:: server
#
# Author:: Joshua Timberman (<joshua@opscode.com>)
# Author:: Lamont Granquist (<lamont@opscode.com>)#
# Copyright 2009-2011, Opscode, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

include_recipe "postgresql::client"

case node[:postgresql][:version]
when "8.3"
  node.default[:postgresql][:ssl] = "off"
else # > 8.3
  node.default[:postgresql][:ssl] = "true"
end

package "postgresql" do
  case node[:platform]
  when "ubuntu"
    case
    when node[:platform_version].to_f <= 10.04 && node[:postgresql][:version].to_f < 9.0
      package_name "postgresql"
    else
      package_name "postgresql-#{node[:postgresql][:version]}"
    end
  else
    package_name "postgresql"
  end
end

if node.default[:postgresql][:ssl] == 'true' &&
  node[:postgresql].has_key?(:ssl_password)

  data_dir = node[:postgresql][:data_dir]
  server_key = File.join(data_dir, 'server.key')
  bash 'generate-ssl-keys' do
    user 'postgres'
    group 'postgres'
    cwd data_dir
    # Steps from http://www.howtoforge.com/postgresql-ssl-certificates
    code <<-EOF
      openssl genrsa -des3 -passout pass:#{node[:postgresql][:ssl_password]} -out server.key 1024;
      openssl rsa -passin pass:#{node[:postgresql][:ssl_password]} -in server.key -out server.key;
      chmod 400 server.key;
      openssl req -new -key server.key -days 3650 -out server.crt -x509 -subj '/C=PH/ST=Metro Manila/L=NA/O=Stiltify/CN=stiltify.com/emailAddress=hello@stiltify.com';
    EOF
    not_if { File.exists?(server_key) }
  end
end


service "postgresql" do
  case node['platform']
  when "ubuntu"
    case
    # PostgreSQL 9.1 on Ubuntu 10.04 gets set up as "postgresql", not "postgresql-9.1"
    # Is this because of the PPA? And is this still the case?
    when node['platform_version'].to_f <= 10.04 && node['postgresql']['version'].to_f < 9.0
      service_name "postgresql-#{node['postgresql']['version']}"
    else
      service_name "postgresql"
    end
  when "debian"
    case
    when node['platform_version'].to_f <= 5.0
      service_name "postgresql-#{node['postgresql']['version']}"
    else
      service_name "postgresql"
    end
  end
  supports :restart => true, :status => true, :reload => true
  action :nothing
end

directory "#{node[:postgresql][:dir]}" do
  owner "postgres"
  group "postgres"
  mode 0600
  recursive true
  action :create
end

template "#{node[:postgresql][:dir]}/postgresql.conf" do
  source "debian.postgresql.conf.erb"
  owner "postgres"
  group "postgres"
  mode 0600
  notifies :restart, resources(:service => "postgresql")
end

if node[:postgresql][:standby]
  # This goes in the data directory; where data is stored
  node_name = Chef::Config[:node_name]
  master_ip = node[:postgresql][:master_ip]
  template "/var/lib/postgresql/#{node[:postgresql][:version]}/main/recovery.conf" do
    source "recovery.conf.erb"
    owner "postgres"
    group "postgres"
    mode 0600
    variables(
      :primary_conninfo => "host=#{master_ip} application_name=#{node_name}",
      :trigger_file => "/var/lib/postgresql/#{node[:postgresql][:version]}/main/trigger"
    )
    notifies :restart, resources(:service => "postgresql")
  end
end

# Copy data files from master to standby. Should only happen once.
if node[:postgresql][:master] && (not node[:postgresql][:standby_ips].empty?)
  node[:postgresql][:standby_ips].each do |address|
    bash "Copy Master data files to Standby" do
      user "root"
      cwd "/var/lib/postgresql/#{node[:postgresql][:version]}/main/"
      code <<-EOH
        invoke-rc.d postgresql stop
        rsync -av --exclude=pg_xlog * #{address}:/var/lib/postgresql/#{node[:postgresql][:version]}/main/
        touch .initial_transfer_complete
        invoke-rc.d postgresql start
      EOH
      not_if do
        File.exists?("/var/lib/postgresql/#{node[:postgresql][:version]}/main/.initial_transfer_complete")
      end
    end
  end
end
