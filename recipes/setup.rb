#
# Cookbook Name:: glance
# Recipe:: setup
#
# Copyright 2012, Rackspace US, Inc.
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


# make sure we die early if there are glance-setups other than us
if get_role_count("glance-setup", false) > 0
  msg = "You can only have one node with the glance-setup role"
  Chef::Application.fatal!(msg)
end

::Chef::Recipe.send(:include, Opscode::OpenSSL::Password)
include_recipe "mysql::client"
include_recipe "mysql::ruby"
include_recipe "monitoring"

platform_options = node["glance"]["platform"]

unless node["glance"]["db"]["password"]
  Chef::Log.info("Running glance setup - setting glance passwords")
end

if node["developer_mode"]
  node.set_unless["glance"]["db"]["password"] = "glance"
else
  node.set_unless["glance"]["db"]["password"] = secure_password
end
node.set_unless["glance"]["service_pass"] = secure_password

# Search for keystone endpoint info
ks_api_role = "keystone-api"
ks_ns = "keystone"
ks_admin_endpoint = get_access_endpoint(ks_api_role, ks_ns, "admin-api")
# Get settings from role[keystone-setup]
keystone = get_settings_by_role("keystone-setup", "keystone")

# creates db and user and returns connection info
mysql_info = create_db_and_user(
  "mysql",
  node["glance"]["db"]["name"],
  node["glance"]["db"]["username"],
  node["glance"]["db"]["password"]
)

mysql_connect_ip = get_access_endpoint('mysql-master', 'mysql', 'db')["host"]

include_recipe "glance::glance-common"

execute "glance-manage db_sync" do
  user "glance"
  group "glance"
  if platform?(%w{ubuntu debian})
    command "glance-manage version_control 0 && glance-manage db_sync"
  end
  if platform?(%w{redhat centos fedora scientific})
    command "glance-manage db_sync"
  end
  # the not_if doesn't run as glance:glance which results in
  # /var/log/glance/registry.log being owned by root:root on CentOS 6.x
  not_if "sudo -u glance glance-manage db_version"
  action :run
end

file "/var/lib/glance/glance.sqlite" do
  action :delete
end

# Register Service Tenant
keystone_tenant "Register Service Tenant" do
  auth_host ks_admin_endpoint["host"]
  auth_port ks_admin_endpoint["port"]
  auth_protocol ks_admin_endpoint["scheme"]
  api_ver ks_admin_endpoint["path"]
  auth_token keystone["admin_token"]
  tenant_name node["glance"]["service_tenant_name"]
  tenant_description "Service Tenant"
  tenant_enabled true # Not required as this is the default
  action :create
end

# Register Service User
keystone_user "Register Service User" do
  auth_host ks_admin_endpoint["host"]
  auth_port ks_admin_endpoint["port"]
  auth_protocol ks_admin_endpoint["scheme"]
  api_ver ks_admin_endpoint["path"]
  auth_token keystone["admin_token"]
  tenant_name node["glance"]["service_tenant_name"]
  user_name node["glance"]["service_user"]
  user_pass node["glance"]["service_pass"]
  user_enabled true # Not required as this is the default
  action :create
end

## Grant Admin role to Service User for Service Tenant ##
keystone_role "Grant 'admin' Role to Service User for Service Tenant" do
  auth_host ks_admin_endpoint["host"]
  auth_port ks_admin_endpoint["port"]
  auth_protocol ks_admin_endpoint["scheme"]
  api_ver ks_admin_endpoint["path"]
  auth_token keystone["admin_token"]
  tenant_name node["glance"]["service_tenant_name"]
  user_name node["glance"]["service_user"]
  role_name node["glance"]["service_role"]
  action :grant
end
