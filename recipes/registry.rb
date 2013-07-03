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

# Find the node that ran the glance-setup recipe and grab his passswords
if Chef::Config[:solo]
  msg = "This recipe uses search. Chef Solo does not support search"
  Chef::Application.fatal!(msg)
else
  # README(shep): recipes brought in via include_recipe are not added
  # to the run_list. I think this makes this the same as
  # node.run_list.expand(node.chef_environment).recipes.include?(<recipe>)
  if node["recipes"].include?("glance::setup")
    msg = "I ran the glance::setup so I will use my own glance passwords"
    Chef::Log.info(msg)
  else
    search_str = "chef_environment:#{node.chef_environment} " +
      "AND roles:glance-setup"
    setup = search(:node, search_str)
    if setup.length == 0
      msg = "You must have run the glance::setup recipe on one node " +
        "already in order to be a glance-registry server."
      Chef::Application.fatal!(msg)
    elsif setup.length == 1
      Chef::Log.info "Found glance::setup node: #{setup[0].name}"
      node.set["glance"]["db"]["password"] =
        setup[0]["glance"]["db"]["password"]
      node.set["glance"]["service_pass"] = setup[0]["glance"]["service_pass"]
    elsif setup.length >1
      msg = "You have specified more than one glance-registry setup node " +
        "and this is not a valid configuration."
      Chef::Application.fatal!(msg)
    end
  end
end

platform_options = node["glance"]["platform"]

registry_endpoint = get_access_endpoint("glance-registry", "glance", "registry")

if registry_endpoint["scheme"] == "https"
  include_recipe "glance::registry-ssl"
else
  apache_site "openstack-glance-registry" do
    enable false
    notifies :run, "execute[restore-selinux-context]", :immediately
    notifies :restart, "service[apache2]", :immediately
  end
end

service "glance-registry" do
  service_name platform_options["glance_registry_service"]
  supports :status => true, :restart => true
  unless registry_endpoint["scheme"] == "https"
    action :enable
    subscribes :restart,
      "template[/etc/glance/glance-registry.conf]",
      :immediately
    subscribes :restart,
      "template[/etc/glance/glance-registry-paste.ini]",
      :immediately
  else
    action [ :disable, :stop ]
  end
end

# glance-api gets pulled in when we install glance-registry.  Unless we are
# meant to be a glance-api node too, make sure it's stopped
service "glance-api" do
  service_name platform_options["glance_api_service"]
  supports :status => true, :restart => true
  action [:stop, :disable]
  not_if {
    node.run_list.expand(node.chef_environment).recipes.include?("glance::api")
  }
end
