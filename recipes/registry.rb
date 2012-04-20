#
# Cookbook Name:: glance
# Recipe:: registry
#
# Copyright 2009, Rackspace Hosting, Inc.
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

include_recipe "mysql::client"

# Distribution specific settings go here
if platform?(%w{fedora})
  # Fedora
  mysql_python_package = "MySQL-python"
  glance_package = "openstack-glance"
  glance_registry_service = "openstack-glance-registry"
  glance_package_options = ""
else
  # All Others (right now Debian and Ubuntu)
  mysql_python_package="python-mysqldb"
  glance_package = "glance"
  glance_registry_service = "glance-registry"
  glance_package_options = "-o Dpkg::Options::='--force-confold' --force-yes"
end

package "python-keystone" do
    action :install
end

if Chef::Config[:solo]
  Chef::Log.warn("This recipe uses search. Chef Solo does not support search.")
else
  # Lookup mysql ip address
  mysql_server, something, result_count = Chef::Search::Query.new.search(:node, "roles:mysql-master AND chef_environment:#{node.chef_environment}")
  if result_count > 0
    Chef::Log.info("mysql: using search")
    db_ip_address = mysql_server[0]['mysql']['bind_address']
    db_root_password = mysql_server[0]['mysql']['server_root_password']
  else
    Chef::Log.info("mysql: NOT using search")
    db_ip_address = node['mysql']['bind_address']
    db_root_password = node['mysql']['server_root_password']
  end

  # Lookup keystone api ip address
  keystone, something, result_count = Chef::Search::Query.new.search(:node, "roles:keystone AND chef_environment:#{node.chef_environment}")
  if result_count > 0
    Chef::Log.info("keystone: using search")
    keystone_api_ip = keystone[0]['keystone']['api_ipaddress']
    keystone_service_port = keystone[0]['keystone']['service_port']
    keystone_admin_port = keystone[0]['keystone']['admin_port']
    keystone_admin_token = keystone[0]['keystone']['admin_token']
  else
    Chef::Log.info("keystone: NOT using search")
    keystone_api_ip = node['keystone']['api_ipaddress']
    keystone_service_port = node['keystone']['service_port']
    keystone_admin_port = node['keystone']['admin_port']
    keystone_admin_token = node['keystone']['admin_token']
  end
end

connection_info = {:host => db_ip_address, :username => "root", :password => db_root_password}
mysql_database "create glance database" do
  connection connection_info
  database_name node["glance"]["db"]
  action :create
end

mysql_database_user node["glance"]["db_user"] do
  connection connection_info
  password node["glance"]["db_passwd"]
  action :create
end

mysql_database_user node["glance"]["db_user"] do
  connection connection_info
  password node["glance"]["db_passwd"]
  database_name node["glance"]["db"]
  host '%'
  privileges [:all]
  action :grant 
end

package "curl" do
  action :install
end

package mysql_python_package do
  action :install
end

package glance_package do
  action :upgrade
end

service glance_registry_service do
  supports :status => true, :restart => true
  action :enable
end

execute "glance-manage db_sync" do
        command "sudo -u glance glance-manage db_sync"
#        environment 'AUTO_REGISTER_DB_MODELS' => "true"
        action :nothing
        notifies :restart, resources(:service => glance_registry_service), :immediately
end

# Having to manually version the database because of Ubuntu bug
# https://bugs.launchpad.net/ubuntu/+source/glance/+bug/981111
# ******** THIS IS A VERY BAD IDEA.. ONLY USEFUL FOR OUR ALLINONE TEST CASE **********
execute "glance-manage version_control" do
  command "sudo -u glance glance-manage version_control 0"
  action :nothing
  not_if "sudo -u glance glance-manage db_version"
  notifies :run, resources(:execute => "glance-manage db_sync"), :immediately
end

file "/var/lib/glance/glance.sqlite" do
    action :delete
end

# Register Service Tenant
keystone_register "Register Service Tenant" do
  auth_host keystone_api_ip
  auth_port keystone_admin_port
  auth_protocol "http"
  api_ver "/v2.0"
  auth_token keystone_admin_token
  tenant_name node["glance"]["service_tenant_name"]
  tenant_description "Service Tenant"
  tenant_enabled "true" # Not required as this is the default
  action :create_tenant
end

# Register Service User
keystone_register "Register Service User" do
  auth_host keystone_api_ip
  auth_port keystone_admin_port
  auth_protocol "http"
  api_ver "/v2.0"
  auth_token keystone_admin_token
  tenant_name node["glance"]["service_tenant_name"]
  user_name node["glance"]["service_user"]
  user_pass node["glance"]["service_pass"]
  user_enabled "true" # Not required as this is the default
  action :create_user
end

## Grant Admin role to Service User for Service Tenant ##
keystone_register "Grant 'admin' Role to Service User for Service Tenant" do
  auth_host keystone_api_ip
  auth_port keystone_admin_port
  auth_protocol "http"
  api_ver "/v2.0"
  auth_token keystone_admin_token
  tenant_name node["glance"]["service_tenant_name"]
  user_name node["glance"]["service_user"]
  role_name node["glance"]["service_role"]
  action :grant_role
end

directory "/etc/glance" do
  action :create
  group "glance"
  owner "glance"
  mode "0700"
  not_if do
    File.exists?("/etc/glance")
  end
end  

template "/etc/glance/glance-registry.conf" do
  source "glance-registry.conf.erb"
  owner "root"
  group "root"
  mode "0644"
  variables(
    :registry_port => node["glance"]["registry_port"],
    :user => node["glance"]["db_user"],
    :passwd => node["glance"]["db_passwd"],
    :ip_address => node["controller_ipaddress"],
    :db_name => node["glance"]["db"],
    :db_ipaddress => db_ip_address,
    :keystone_api_ipaddress => keystone_api_ip,
    :service_port => keystone_service_port,
    :admin_port => keystone_admin_port,
    :admin_token => keystone_admin_token,
    :service_tenant_name => node["glance"]["service_tenant_name"],
    :service_user => node["glance"]["service_user"],
    :service_pass => node["glance"]["service_pass"]
  )
  notifies :run, resources(:execute => "glance-manage version_control"), :immediately
  # notifies :run, resources(:execute => "glance-manage db_sync"), :immediately
end

template "/etc/glance/glance-registry-paste.ini" do
  source "glance-registry-paste.ini.erb"
  owner "root"
  group "root"
  mode "0644"
  variables(
    :ip_address => node["controller_ipaddress"],
    :keystone_api_ipaddress => keystone_api_ip,
    :service_port => keystone_service_port,
    :admin_port => keystone_admin_port,
    :admin_token => keystone_admin_token,
    :service_tenant_name => node["glance"]["service_tenant_name"],
    :service_user => node["glance"]["service_user"],
    :service_pass => node["glance"]["service_pass"]
  )
  notifies :restart, resources(:service => glance_registry_service), :immediately
end
