#
# Cookbook Name:: glance
# Recipe:: api
#
# Copyright 2012-2013, Rackspace US, Inc.
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

include_recipe "glance::glance-common"

platform_options = node["glance"]["platform"]

api_endpoint = get_bind_endpoint("glance", "api")
internal_api_endpoint = get_bind_endpoint("glance", "internal-api")
admin_api_endpoint = get_bind_endpoint("glance", "admin-api")

if api_endpoint["scheme"] == "https"
  include_recipe "glance::api-ssl"
else
  if node.recipe?"apache2"
    apache_site "openstack-glance-api" do
      enable false
      notifies :restart, "service[apache2]", :immediately
    end
  end
end

service "glance-api" do
  service_name platform_options["glance_api_service"]
  supports :status => true, :restart => true
  unless api_endpoint["scheme"] == "https"
    action :enable
    subscribes :restart, "template[/etc/glance/glance-api.conf]", :immediately
    subscribes :restart,
      "template[/etc/glance/glance-api-paste.ini]",
      :immediately
  else
    action [ :disable, :stop ]
  end
end

# glance-registry gets pulled in when we install glance-api.  Unless we are
# meant to be a glance-registry node too, make sure it's stopped
service "glance-registry" do
  service_name platform_options["glance_registry_service"]
  supports :status => true, :restart => true
  action [:stop, :disable]
  not_if {
    node.run_list.expand(
      node.chef_environment).recipes.include?("glance::registry")
  }
end

# Search for keystone endpoint info
ks_api_role = "keystone-api"
ks_ns = "keystone"
ks_admin_endpoint = get_access_endpoint(ks_api_role, ks_ns, "admin-api")

# Get settings from role[keystone-setup]
keystone = get_settings_by_role("keystone-setup", "keystone")

# Configure glance-cache-pruner to run every 30 minutes
cron "glance-cache-pruner" do
  minute "*/30"
  command "/usr/bin/glance-cache-pruner"
end

# Configure glance-cache-cleaner to run at 00:01 everyday
cron "glance-cache-cleaner" do
  minute "01"
  hour "00"
  command "/usr/bin/glance-cache-cleaner"
end

# Register Image Service
keystone_service "Register Image Service" do
  auth_host ks_admin_endpoint["host"]
  auth_port ks_admin_endpoint["port"]
  auth_protocol ks_admin_endpoint["scheme"]
  api_ver ks_admin_endpoint["path"]
  auth_token keystone["admin_token"]
  service_name "glance"
  service_type "image"
  service_description "Glance Image Service"
  action :create
end

# Register Image Endpoint
keystone_endpoint "Register Image Endpoint" do
  auth_host ks_admin_endpoint["host"]
  auth_port ks_admin_endpoint["port"]
  auth_protocol ks_admin_endpoint["scheme"]
  api_ver ks_admin_endpoint["path"]
  auth_token keystone["admin_token"]
  service_type "image"
  endpoint_region node["osops"]["region"]
  endpoint_adminurl admin_api_endpoint["uri"]
  endpoint_internalurl internal_api_endpoint["uri"]
  endpoint_publicurl api_endpoint["uri"]
  action :recreate
end

if node["glance"]["image_upload"]
  node["glance"]["images"].each do |img|
    Chef::Log.info("Checking to see if #{img.to_s}-image should be uploaded.")

    keystone_admin_user = keystone["admin_user"]
    keystone_admin_password = keystone["users"][keystone_admin_user]["password"]
    keystone_tenant = keystone["users"][keystone_admin_user]["default_tenant"]

    glance_image "Image setup for #{img.to_s}" do
      image_url node["glance"]["image"][img.to_sym]
      image_name img
      keystone_user keystone_admin_user
      keystone_pass keystone_admin_password
      keystone_tenant keystone_tenant
      keystone_uri ks_admin_endpoint["uri"]
      scheme api_endpoint["scheme"]
      action :upload
    end
  end
end
