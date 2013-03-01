#
# Cookbook Name:: glance
# Recipe:: replicator
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

glance_servers = get_realserver_endpoints("glance-api", "glance", "api").map { |g| g["host"] }
me = get_ip_for_net(node["glance"]["services"]["api"]["network"], node)
glance_servers.delete(me)
# This recipe is only called when we have 2 glance-api servers, so there should
# only be one left once we remove ourself.
other_glance_server_ip = glance_servers[0]
other_glance_server_node = search(:node, "chef_environment:#{node.chef_environment} AND network_*_addresses:#{other_glance_server_ip}")[0]
other_glance_server_port = other_glance_server_node["openssh"]["server"]["port"]
glance_endpoint = get_access_endpoint("glance-api", "glance", "api")

dsh_group "glance" do
  user "root"
  admin_user "root"
  group "root"
end

template "/var/lib/glance/glance-replicator.py" do
  source "glance-replicator.py.erb"
  owner "glance"
  group "glance"
  mode "0755"
  variables(
      :other_glance_server_ip => other_glance_server_ip,
      :other_glance_server_port => other_glance_server_port
  )
end

template "/var/lib/glance/glance-replicator.sh" do
  source "glance-replicator.sh.erb"
  owner "root"
  group "root"
  mode "0755"
  variables(
      :glance_ip => glance_endpoint["host"],
      :glance_port => glance_endpoint["port"]
  )
end

cron "glance-replicator" do
  minute "*/#{node['glance']['replicator']['interval']}"
  command "/var/lib/glance/glance-replicator.sh"
end
