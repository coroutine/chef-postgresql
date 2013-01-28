#
# Cookbook Name:: postgresql
# Recipe:: setup
#
# Copyright 2012, Coroutine LLC
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
# --------------------------------------
# Sample Item from the specified Databag
# --------------------------------------
# {
#    "id": "postgresql_setup_wfp",
#    "users": [
#        {
#            "username":"some_user",
#            "password":"some_password",
#            "superuser": "true",
#        }
#    ],
#    "databases": [
#        {
#            "name":"some_db",
#            "owner":"some_user",
#            "template":"template0",
#            "encoding": "UTF8",
#            "locale": "en_US.utf8"
#        }
#    ]
# }
# --------------------------------------


# Fetch the setup items from the Databag; It contains things like Datase users,
# passwords, DB names and encoding.
setup_items = []
node['postgresql']['setup_items'].each do |itemname|
  databag = node['postgresql']['databag']
  if Chef::Config[:solo]
    i = data_bag_item(databag,  itemname.gsub(/[.]/, '-'))
    setup_items << i
  else
    item = "id:#{itemname}"

    search(databag, item) do |i|
      setup_items << i
    end
  end
end

# We use a mix of psql commands and SQL statements to create users.
#
# To Create a User:
#     sudo -u postgres createuser -s some_user
#
# To set their password:
#     sudo -u postgres psql -c "ALTER USER some_user WITH PASSWORD 'secret';"
#
# To create a Database
#     sudo -u postgres createdb -E UTF8 -O some_user \
#          -T template0 database_name --local=en_US.utf8
#
# To make these idempotent, we test for existing users/databases;
# Test for existing DB:
#     sudo -u postgres psql -l | grep database_name
#
# Test for existing Users
#     sudo -u postgres psql -c "\du" | grep some_user

setup_items.each do |setup|

  setup["users"].each do |user|

    create_user_command = begin
      if user['superuser']
        "sudo -u postgres createuser -s #{user['username']};"
      else
        "sudo -u postgres createuser #{user['username']};"
      end
    end

    set_user_password = begin
        "sudo -u postgres psql -c \"ALTER USER #{user['username']} " +
        "WITH PASSWORD '#{user['password']}';\""
    end

    bash "create_user" do
      user "root"
      code <<-EOH
        #{create_user_command} #{set_user_password}
      EOH
      not_if "sudo -u postgres psql -c \"\\du\" | grep #{user['username']}"
    end
  end

  setup["databases"].each do |db|

    create_database_command = begin
      "sudo -u postgres createdb -E #{db['encoding']} -O #{db['owner']} " +
      "--locale #{db['locale']} -T #{db['template']} #{db['name']}"
    end

    bash "create_database" do
      user "root"
      code <<-EOH
        #{create_database_command}
      EOH
      not_if "sudo -u postgres psql -l | grep #{db['name']}"
    end
  end # End DB setup

end
