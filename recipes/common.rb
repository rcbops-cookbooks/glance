#
# Cookbook Name:: glance
# Recipe:: common
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

if not node['package_component'].nil?
    release = node['package_component']
else
    release = "folsom"
end

platform_options = node["glance"]["platform"][release]

Chef::Log.info(platform_options)

service "glance-api" do
  service_name platform_options["glance_api_service"]
  supports :status => true, :restart => true
  if node.run_list.expand(node.chef_environment).recipes.include?("glance::api")
    action :enable
  else
    action [ :stop, :disable ]
  end
end

service "glance-registry" do
  service_name platform_options["glance_registry_service"]
  supports :status => true, :restart => true
  if node.run_list.expand(node.chef_environment).recipes.include?("glance::registry")
    action :enable
  else
    action [ :stop, :disable ]
  end
end
