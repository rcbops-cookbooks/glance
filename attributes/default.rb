#
# Cookbook Name:: glance
# Attributes:: glance
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

default["glance"]["api"]["bind_address"] = "0.0.0.0"
default["glance"]["api"]["port"] = "9292"
default["glance"]["api"]["ip_address"] = node["ipaddress"]
default["glance"]["api"]["protocol"] = "http"
default["glance"]["api"]["version"] = "v1"
default["glance"]["api"]["adminURL"] = "#{node["glance"]["api"]["protocol"]}://#{node["glance"]["api"]["ip_address"]}:#{node["glance"]["api"]["port"]}/#{node["glance"]["api"]["version"]}"
default["glance"]["api"]["internalURL"] = node["glance"]["api"]["adminURL"]
default["glance"]["api"]["publicURL"] = node["glance"]["api"]["adminURL"]

default["glance"]["registry"]["bind_address"] = "0.0.0.0"
default["glance"]["registry"]["port"] = "9191"
default["glance"]["registry"]["ip_address"] = node["ipaddress"]

default["glance"]["db"]["name"] = "glance"
default["glance"]["db"]["username"] = "glance"
# Replacing with OpenSSL::Password in recipes/registry.rb
# default["glance"]["db"]["password"] = "glance"

# TODO: These may need to be glance-registry specific.. and looked up by glance-api
default["glance"]["service_tenant_name"] = "service"
default["glance"]["service_user"] = "glance"
# Replacing with OpenSSL::Password in recipes/registry.rb
# default["glance"]["service_pass"] = "vARxre7K"
default["glance"]["service_role"] = "admin"

default["glance"]["image_upload"] = false
default["glance"]["images"] = [ "tty" ]
default["glance"]["image"]["oneiric"] = "http://c250663.r63.cf1.rackcdn.com/ubuntu-11.10-server-uec-amd64-multinic.tar.gz"
default["glance"]["image"]["natty"] = "http://c250663.r63.cf1.rackcdn.com/ubuntu-11.04-server-uec-amd64-multinic.tar.gz"
default["glance"]["image"]["maverick"] = "http://c250663.r63.cf1.rackcdn.com/ubuntu-10.10-server-uec-amd64-multinic.tar.gz"
#default["glance"]["image"]["tty"] = "http://smoser.brickies.net/ubuntu/ttylinux-uec/ttylinux-uec-amd64-12.1_2.6.35-22_1.tar.gz"
default["glance"]["image"]["tty"] = "http://c250663.r63.cf1.rackcdn.com/ttylinux.tgz"
