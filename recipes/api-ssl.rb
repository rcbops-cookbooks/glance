#
# Cookbook Name:: glance
# Recipe:: api-ssl
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

include_recipe "apache2"
include_recipe "apache2::mod_wsgi"
include_recipe "apache2::mod_rewrite"
include_recipe "osops-utils::mod_ssl"
include_recipe "osops-utils::ssl_packages"

# Remove monit file if it exists
if node.attribute?"monit"
  if node["monit"].attribute?"conf.d_dir"
    file "#{node['monit']['conf.d_dir']}/glance-api.conf" do
      action :delete
      notifies :reload, "service[monit]", :immediately
    end
  end
end

# setup cert files
case node["platform"]
when "ubuntu", "debian"
  grp = "ssl-cert"
else
  grp = "root"
end

cookbook_file "#{node["glance"]["ssl"]["dir"]}/certs/#{node["glance"]["services"]["api"]["cert_file"]}" do
  source "glance_api.pem"
  mode 0644
  owner "root"
  group "root"
end

cookbook_file "#{node["glance"]["ssl"]["dir"]}/private/#{node["glance"]["services"]["api"]["key_file"]}" do
  source "glance_api.key"
  mode 0644
  owner "root"
  group grp
end

unless node["glance"]["services"]["api"]["chain_file"].nil?
  cookbook_file "#{node["glance"]["ssl"]["dir"]}/certs/#{node["glance"]["services"]["api"]["chain_file"]}" do
    source node["glance"]["services"]["api"]["chain_file"]
    mode 0644
    owner "root"
    group "root"
  end
end

# setup wsgi file

directory "#{node["apache"]["dir"]}/wsgi" do
  action :create
  owner "root"
  group "root"
  mode "0755"
end

cookbook_file "#{node["apache"]["dir"]}/wsgi/#{node["glance"]["services"]["api"]["wsgi_file"]}" do
  source "api_modwsgi.py"
  mode 0644
  owner "root"
  group "root"
end

glance_api_bind = get_bind_endpoint("glance", "api")

unless node["glance"]["services"]["api"].attribute?"cert_override"
  cert_location = "#{node["glance"]["ssl"]["dir"]}/certs/#{node["glance"]["services"]["api"]["cert_file"]}"
else
  cert_location = node["glance"]["services"]["api"]["cert_override"]
end

unless node["glance"]["services"]["api"].attribute?"key_override"
  key_location = "#{node["glance"]["ssl"]["dir"]}/private/#{node["glance"]["services"]["api"]["key_file"]}"
else
  key_location = node["glance"]["services"]["api"]["key_override"]
end

unless node["glance"]["services"]["api"]["chain_file"].nil?
  chain_location = "#{node["glance"]["ssl"]["dir"]}/certs/#{node["glance"]["services"]["api"]["chain_file"]}"
else
  chain_location = "donotset"
end

template value_for_platform(
  ["ubuntu", "debian", "fedora"] => {
    "default" => "#{node["apache"]["dir"]}/sites-available/openstack-glance-api"
  },
  "fedora" => {
    "default" => "#{node["apache"]["dir"]}/vhost.d/openstack-glance-api"
  },
  ["redhat", "centos"] => {
    "default" => "#{node["apache"]["dir"]}/conf.d/openstack-glance-api"
  },
  "default" => {
    "default" => "#{node["apache"]["dir"]}/openstack-glance-api"
  }
) do
  source "modwsgi_vhost.erb"
  owner "root"
  group "root"
  mode "0644"
  variables(
    :listen_ip => glance_api_bind["host"],
    :service_port => glance_api_bind["port"],
    :cert_file => cert_location,
    :key_file => key_location,
    :chain_file => chain_location,
    :wsgi_file  => "#{node["apache"]["dir"]}/wsgi/#{node["glance"]["services"]["api"]["wsgi_file"]}",
    :proc_group => "glance-api",
    :log_file => "/var/log/glance/glance-api.log"
  )
  notifies :reload, "service[apache2]", :delayed
end

apache_site "openstack-glance-api" do
  enable true
  notifies :restart, "service[apache2]", :immediately
end
