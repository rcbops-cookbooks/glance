#
# Cookbook Name:: glance
# Recipe:: api
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

platform_options = node["glance"]["platform"]

package "curl" do
  action :upgrade
end

package "python-keystone" do
    action :install
end

platform_options["glance_packages"].each do |pkg|
  package pkg do
    action :upgrade
  end
end

service "glance-api" do
  service_name platform_options["glance_api_service"]
  supports :status => true, :restart => true
  action :enable
end

directory "/etc/glance" do
  action :create
  group "glance"
  owner "glance"
  mode "0700"
end

# FIXME: seems like misfeature
template "/etc/glance/policy.json" do
  source "policy.json.erb"
  owner "root"
  group "root"
  mode "0644"
  notifies :restart, resources(:service => "glance-api"), :immediately
  not_if do
    File.exists?("/etc/glance/policy.json")
  end
end

rabbit_info = get_settings_by_role("rabbitmq-server", "rabbitmq") # FIXME: access

ks_admin_endpoint = get_access_endpoint("keystone", "keystone", "admin-api")
ks_service_endpoint = get_access_endpoint("keystone", "keystone","service-api")
keystone = get_settings_by_role("keystone", "keystone")

registry_endpoint = get_access_endpoint("glance-registry", "glance", "registry")
api_endpoint = get_bind_endpoint("glance", "api")

template "/etc/glance/glance-api.conf" do
  source "glance-api.conf.erb"
  owner "root"
  group "root"
  mode "0644"
  variables(
    "api_bind_address" => api_endpoint["host"],
    "api_bind_port" => api_endpoint["port"],
    "registry_ip_address" => registry_endpoint["host"],
    "registry_port" => registry_endpoint["port"],
    "rabbit_ipaddress" => rabbit_info["ipaddress"]    #FIXME!
  )
  notifies :restart, resources(:service => "glance-api"), :immediately
end

template "/etc/glance/glance-api-paste.ini" do
  source "glance-api-paste.ini.erb"
  owner "root"
  group "root"
  mode "0644"
  variables(
    "keystone_api_ipaddress" => ks_admin_endpoint["host"],
    "keystone_service_port" => ks_service_endpoint["port"],
    "keystone_admin_port" => ks_admin_endpoint["port"],
    "keystone_admin_token" => keystone["admin_token"],
    "service_tenant_name" => node["glance"]["service_tenant_name"],
    "service_user" => node["glance"]["service_user"],
    "service_pass" => node["glance"]["service_pass"]
  )
  notifies :restart, resources(:service => "glance-api"), :immediately
end

template "/etc/glance/glance-scrubber.conf" do
  source "glance-scrubber.conf.erb"
  owner "root"
  group "root"
  mode "0644"
  variables(
    "registry_ip_address" => registry_endpoint["host"],
    "registry_port" => registry_endpoint["port"]
  )
end

template "/etc/glance/glance-scrubber-paste.ini" do
  source "glance-scrubber-paste.ini.erb"
  owner "root"
  group "root"
  mode "0644"
end

# Register Image Service
keystone_register "Register Image Service" do
  auth_host ks_admin_endpoint["host"]
  auth_port ks_admin_endpoint["port"]
  auth_protocol ks_admin_endpoint["scheme"]
  api_ver ks_admin_endpoint["path"]
  auth_token keystone["admin_token"]
  service_name "glance"
  service_type "image"
  service_description "Glance Image Service"
  action :create_service
end

# Register Image Endpoint
keystone_register "Register Image Endpoint" do
  auth_host ks_admin_endpoint["host"]
  auth_port ks_admin_endpoint["port"]
  auth_protocol ks_admin_endpoint["scheme"]
  api_ver ks_admin_endpoint["path"]
  auth_token keystone["admin_token"]
  service_type "image"
  endpoint_region "RegionOne"
  endpoint_adminurl api_endpoint["uri"]
  endpoint_internalurl api_endpoint["uri"]
  endpoint_publicurl api_endpoint["uri"]
  action :create_endpoint
end

if node["glance"]["image_upload"]
  # TODO(breu): the environment needs to be derived from a search
  # TODO(shep): this whole bit is super dirty.. and needs some love.
  node["glance"]["images"].each do |img|
    Chef::Log.info("Checking to see if #{img.to_s}-image should be uploaded.")
    bash "default image setup for #{img.to_s}" do
      cwd "/tmp"
      user "root"
      environment ({"OS_USERNAME" => keystone["admin_user"],
                    "OS_PASSWORD" => admin_password,
                    "OS_TENANT_NAME" => admin_tenant_name,
                    "OS_AUTH_URL" => ks_admin_endpoint["uri"]})
      code <<-EOH
        set -e
        set -x
        mkdir -p images

        curl #{node["glance"]["image"][img.to_sym]} | tar -zx -C images/
        image_name=$(basename #{node["glance"]["image"][img]} .tar.gz)

        image_name=${image_name%-multinic}

        kernel_file=$(ls images/*vmlinuz-virtual | head -n1)
        if [ ${#kernel_file} -eq 0 ]; then
           kernel_file=$(ls images/*vmlinuz | head -n1)
        fi

        ramdisk=$(ls images/*-initrd | head -n1)
        if [ ${#ramdisk} -eq 0 ]; then
            ramdisk=$(ls images/*-loader | head -n1)
        fi

        kernel=$(ls images/*.img | head -n1)

        kid=$(glance --silent-upload add name="${image_name}-kernel" is_public=true disk_format=aki container_format=aki < ${kernel_file} | cut -d: -f2 | sed 's/ //')
        rid=$(glance --silent-upload add name="${image_name}-initrd" is_public=true disk_format=ari container_format=ari < ${ramdisk} | cut -d: -f2 | sed 's/ //')
        glance --silent-upload add name="#{img.to_s}-image" is_public=true disk_format=ami container_format=ami kernel_id=$kid ramdisk_id=$rid < ${kernel}
      EOH
      not_if "glance -f -I admin -K #{admin_password} -T #{admin_tenant_name} -N #{ks_admin_endpoint["uri"]} index | grep #{img.to_s}-image"
    end
  end
end
