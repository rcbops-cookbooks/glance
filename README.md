Description
===========

Installs the OpenStack Image Repository/Server (codename: glance) from packages. Optionally populates the repository with some default images 

http://glance.openstack.org/

Requirements
============

Chef 0.10.0 or higher required (for Chef environment use).

Platform
--------

* Ubuntu-12.04
* Fedora-17

Cookbooks
---------

The following cookbooks are dependencies:

* database
* mysql
* keystone


Resources/Providers
===================

None


Recipes
=======

default
-------

The default recipe includes the api and registry recipes.

api
------

The api recipe will install the glance-api server

registry
--------

The registry recipe will install the glance-registry server


Data Bags
=========

None


Attributes 
==========

* `glance["db"]["name"]` - name of glance database
* `glance["db"]["user"]` - username for glance database access
* `glance["db"]["password"]` - password for glance database access
* `glance["api"]["ip_address"]` - ip address to use for communicating with the glance api
* `glance["api"]["bind_address"]` - ip address for the glance api to bind to
* `glance["api"]["port"]` - port for the glance api to bind to
* `glance["api"]["adminURL"]` - used when registering image endpoint with keystone
* `glance["api"]["internalURL"]` - used when registering image endpoint with keystone
* `glance["api"]["publicURL"]` - used when registering image endpoint with keystone
* `glance["registry"]["ip_address"]` - ip address to use for communicating with the glance registry
* `glance["registry"]["bind_address"]` - ip address for the glance registry to bind to
* `glance["registry"]["port"]` - ip address for the glance port to bind to
* `glance["service_tenant_name"]` - tenant name used by glance when interacting with keystone - used in the api and registry paste.ini files
* `glance["service_user"]` - user name used by glance when interacting with keystone -  used in the api and registry paste.ini files
* `glance["service_pass"]` - user password used by glance when interacting with keystone - used in the api and registry paste.ini files
* `glance["service_role"]` - user role used by glance when interacting with keystone - used in the api and registry paste.ini files
* `glance["image_upload"]` - toggles whether to automatically upload images in the `glance["images"]` array
* `glance["images"]` - default list of images to upload to the glance repository as part of the install
* `glance["image]["<imagename>"]` - url location of the <imagename> image. There can be multiple instances of this line to define multiple imagess (eg natty, maverick, fedora17 etc)
--- example `glance["image]["natty"]` - "http://c250663.r63.cf1.rackcdn.com/ubuntu-11.04-server-uec-amd64-multinic.tar.gz"


Templates
=========

* `glance-api-paste.ini.erb` - paste config for glance-api middleware
* `glance-api.conf.erb` - config file for glance-api server
* `glance-registry-paste.ini.erb` - paste config for glance-registry middleware
* `glance-registry.conf.erb` - config file for glance-registry server
* `glance-scrubber.conf.erb` - config file for glance image scrubber service
* `policy.json.erb` - for configuration of acls for glance api server


License and Author
==================

Author:: Justin Shepherd (<justin.shepherd@rackspace.com>)  
Author:: Jason Cannavale (<jason.cannavale@rackspace.com>)  
Author:: Ron Pedde (<ron.pedde@rackspace.com>)  
Author:: Joseph Breu (<joseph.breu@rackspace.com>)  
Author:: William Kelly (<william.kelly@rackspace.com>)  
Author:: Darren Birkett (<darren.birkett@rackspace.co.uk>)  
Author:: Evan Callicoat (<evan.callicoat@rackspace.com>)  

Copyright 2012, Rackspace, Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
