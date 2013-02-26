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
  release = "folsom"
end

platform_options = node["glance"]["platform"][release]

# Find the node that ran the glance-setup recipe and grab his passswords
if Chef::Config[:solo]
  Chef::Application.fatal! "This recipe uses search. Chef Solo does not support search."
else
  if node.run_list.expand(node.chef_environment).recipes.include?("glance::setup")
    Chef::Log.info("I ran the glance::setup so I will use my own glance passwords")
  else
    setup = search(:node, "chef_environment:#{node.chef_environment} AND roles:glance-setup")
    if setup.length == 0
      Chef::Application.fatal! "You must have run the glance::setup recipe on one node already in order to be a glance-registry server."
    elsif setup.length == 1
      if node["glance"]["api"]["default_store"] == "file"
        Chef::Application.fatal! "Local file store not supported with multiple glance-registry nodes.
        Change file store to 'swift' or 'cloudfiles' or remove additional glance-registry nodes"
      else
        Chef::Log.info "Found glance::setup node: #{setup[0].name}"
        node.set["glance"]["db"]["password"] = setup[0]["glance"]["db"]["password"]
        node.set["glance"]["service_pass"] = setup[0]["glance"]["service_pass"]
      end
    elsif setup.length >1
      Chef::Application.fatal! "You have specified more than one glance-registry setup node and this is not a valid configuration."
    end
  end
end

package "python-keystone" do
    action :install
end

ks_admin_endpoint = get_access_endpoint("keystone-api", "keystone", "admin-api")
ks_service_endpoint = get_access_endpoint("keystone-api", "keystone", "service-api")
keystone = get_settings_by_role("keystone", "keystone")

registry_endpoint = get_bind_endpoint("glance", "registry")
mysql_info = get_access_endpoint("mysql-master", "mysql", "db")

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

unless node.run_list.expand(node.chef_environment).recipes.include?("glance::api")
  service "glance-api" do
    service_name platform_options["glance_api_service"]
    supports :status => true, :restart => true
    action [ :stop, :disable ]
  end
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

directory "/etc/glance" do
  action :create
  group "glance"
  owner "glance"
  mode "0700"
end

template "/etc/glance/logging.conf" do
  source "glance-logging.conf.erb"
  owner "glance"
  group "glance"
  mode "0640"
  variables(
    "use_syslog" => node["glance"]["syslog"]["use"],
    "log_facility" => node["glance"]["syslog"]["facility"]
  )
  notifies :restart, resources(:service => "glance-registry"), :delayed
end

template "/etc/glance/glance-registry.conf" do
  source "#{release}/glance-registry.conf.erb"
  owner "glance"
  group "glance"
  mode "0600"
  variables(
    "registry_bind_address" => registry_endpoint["host"],
    "registry_port" => registry_endpoint["port"],
    "db_ip_address" => mysql_info["host"],
    "db_user" => node["glance"]["db"]["username"],
    "db_password" => node["glance"]["db"]["password"],
    "db_name" => node["glance"]["db"]["name"],
    "use_syslog" => node["glance"]["syslog"]["use"],
    "log_facility" => node["glance"]["syslog"]["facility"]
  )
end

template "/etc/glance/glance-registry-paste.ini" do
  source "#{release}/glance-registry-paste.ini.erb"
  owner "glance"
  group "glance"
  mode "0600"
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

