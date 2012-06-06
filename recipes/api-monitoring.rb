#
# Cookbook Name:: glance
# Recipe:: api-monitoring
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

########################################
# BEGIN COLLECTD SECTION
# TODO(shep): This needs to be encased in an if block for the collectd_enabled environment toggle

include_recipe "collectd-graphite::collectd-client"

cookbook_file File.join(node['collectd']['plugin_dir'], "glance_plugin.py") do
  source "glance_plugin.py"
  owner "root"
  group "root"
  mode "0644"
end

ks_service_endpoint = get_access_endpoint("keystone", "keystone","service-api")
glance = get_settings_by_role("glance-api", "glance")

collectd_python_plugin "glance_plugin" do
  options(
    "Username"=>glance["service_user"],
    "Password"=>glance["service_pass"],
    "TenantName"=>glance["service_tenant_name"],
    "AuthURL"=>ks_service_endpoint["url"]
  )
end
########################################


########################################
# BEGIN MONIT SECTION
# TODO(shep): This needs to be encased in an if block for the monit_enabled environment toggle

include_recipe "monit::server"

platform_options = node["glance"]["platform"]
monit_procmon "glance-api" do
  process_name "glance-api"
  start_cmd platform_options["monit_commands"]["glance-api"]["start"]
  stop_cmd platform_options["monit_commands"]["glance-api"]["stop"]
end
########################################
