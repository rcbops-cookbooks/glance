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
include_recipe "glance::glance-common"
include_recipe "monitoring"

platform_options = node["glance"]["platform"]

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
      Chef::Log.info "Found glance::setup node: #{setup[0].name}"
      node.set["glance"]["db"]["password"] = setup[0]["glance"]["db"]["password"]
      node.set["glance"]["service_pass"] = setup[0]["glance"]["service_pass"]
    elsif setup.length >1
      Chef::Application.fatal! "You have specified more than one glance-registry setup node and this is not a valid configuration."
    end
  end
end

ks_service_endpoint = get_access_endpoint("keystone-api", "keystone", "service-api")
keystone = get_settings_by_role("keystone", "keystone")
registry_endpoint = get_bind_endpoint("glance", "registry")
mysql_info = get_access_endpoint("mysql-master", "mysql", "db")

service "glance-registry" do
  service_name platform_options["glance_registry_service"]
  supports :status => true, :restart => true
  action :enable
  subscribes :restart, "template[/etc/glance/glance-registry.conf]", :immediately
  subscribes :restart, "template[/etc/glance/glance-registry-paste.ini]", :immediately
end

# glance-api gets pulled in when we install glance-registry.  Unless we are
# meant to be a glance-api node too, make sure it's stopped
service "glance-api" do
  service_name platform_options["glance_api_service"]
  supports :status => true, :restart => true
  action [ :stop, :disable ]
  not_if { node.run_list.expand(node.chef_environment).recipes.include?("glance::api") }
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
