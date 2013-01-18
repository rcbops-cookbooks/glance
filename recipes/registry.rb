#
# Cookbook Name:: glance
# Recipe:: registry
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

::Chef::Recipe.send(:include, Opscode::OpenSSL::Password)
include_recipe "mysql::client"
include_recipe "mysql::ruby"
include_recipe "glance::glance-rsyslog"
include_recipe "monitoring"

if not node["package_component"].nil?
    release = node["package_component"]
else
    release = "essex-final"
end

platform_options = node["glance"]["platform"][release]

# are there any other glance-registry out there? if so grab the passwords off them
if other_registry = get_settings_by_role("glance-registry", "glance", false)
  if  node["glance"]["api"]["default_store"] == "file"
    Chef::Application.fatal! "Local file store not supported with multiple glance-registry nodes. 
    Change file store to 'swift' or 'cloudfiles' or remove additional glance-registry nodes"
  else
    Chef::Log.info("There is at least one other glance-registry node - syncing glance passwords with it/them")
    node.set["glance"]["db"]["password"] = other_registry["db"]["password"]
    node.set["glance"]["service_pass"] = other_registry["service_pass"]
  end
else
  Chef::Log.info("I am currently the only glance-registry node - setting passwords myself")
  if node["developer_mode"]
    node.set_unless["glance"]["db"]["password"] = "glance"
  else
    node.set_unless["glance"]["db"]["password"] = secure_password
  end
  node.set_unless["glance"]["service_pass"] = secure_password
end

package "python-keystone" do
    action :install
end

ks_admin_endpoint = get_access_endpoint("keystone", "keystone", "admin-api")
ks_service_endpoint = get_access_endpoint("keystone", "keystone", "service-api")
keystone = get_settings_by_role("keystone", "keystone")

registry_endpoint = get_bind_endpoint("glance", "registry")

#creates db and user
#returns connection info
#defined in osops-utils/libraries
mysql_info = create_db_and_user("mysql",
                                node["glance"]["db"]["name"],
                                node["glance"]["db"]["username"],
                                node["glance"]["db"]["password"])

package "curl" do
  action :install
end

platform_options["mysql_python_packages"].each do |pkg|
  package pkg do
    action :install
  end
end

platform_options["glance_packages"].each do |pkg|
  package pkg do
    action :install
    options platform_options["package_overrides"]
  end
end

service "glance-registry" do
  service_name platform_options["glance_registry_service"]
  supports :status => true, :restart => true
  action :nothing
end

monitoring_procmon "glance-registry" do
  sname = platform_options["glance_registry_service"]
  pname = platform_options["glance_registry_process_name"]
  process_name pname
  script_name sname
end

monitoring_metric "glance-registry-proc" do
  type "proc"
  proc_name "glance-registry"
  proc_regex platform_options["glance_registry_service"]

  alarms(:failure_min => 2.0)
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
  tenant_enabled "true" # Not required as this is the default
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
  user_enabled "true" # Not required as this is the default
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

directory "/etc/glance" do
  action :create
  group "glance"
  owner "glance"
  mode "0700"
end

template "/etc/glance/glance-registry.conf" do
  source "#{release}/glance-registry.conf.erb"
  owner "root"
  group "root"
  mode "0644"
  variables(
    "registry_bind_address" => registry_endpoint["host"],
    "registry_port" => registry_endpoint["port"],
    "db_ip_address" => mysql_info["bind_address"],
    "db_user" => node["glance"]["db"]["username"],
    "db_password" => node["glance"]["db"]["password"],
    "db_name" => node["glance"]["db"]["name"],
    "use_syslog" => node["glance"]["syslog"]["use"],
    "log_facility" => node["glance"]["syslog"]["facility"]
  )
end

execute "glance-manage db_sync" do
  if platform?(%w{ubuntu debian})
    command "sudo -u glance glance-manage version_control 0 && sudo -u glance glance-manage db_sync"
  end
  if platform?(%w{redhat centos fedora scientific})
    command "sudo -u glance glance-manage db_sync"
  end
  not_if "sudo -u glance glance-manage db_version"
  action :run
end

template "/etc/glance/glance-registry-paste.ini" do
  source "#{release}/glance-registry-paste.ini.erb"
  owner "root"
  group "root"
  mode "0644"
  variables(
    "keystone_api_ipaddress" => ks_admin_endpoint["host"],
    "keystone_service_port" => ks_service_endpoint["port"],
    "keystone_admin_port" => ks_admin_endpoint["port"],
    "service_tenant_name" => node["glance"]["service_tenant_name"],
    "service_user" => node["glance"]["service_user"],
    "service_pass" => node["glance"]["service_pass"]
  )
  notifies :restart, resources(:service => "glance-registry"), :immediately
  notifies :enable, resources(:service => "glance-registry"), :immediately
end

