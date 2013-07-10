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
