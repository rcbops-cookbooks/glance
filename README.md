Description
===========

Installs the OpenStack Image Repository/Server (codename: glance) from packages. Optionally populates the repository with some default images.

http://glance.openstack.org/

Usage
=====

The Glance cookbook currently supports file, swift, and Rackspace Cloud Files (swift API compliant) backing stores.  NOTE: changing the storage location from cloudfiles to swift (and vice versa) requires that you manually export and import your stored images.

To enable these features set the following in the default attributes section in your environment:

Files
-----
    "glance": {
      "api": {
        "default_store": "file"
      },
      "images": [
        "cirros"
      ],
      "image_upload": true
    }


Swift
-----
    "glance": {
      "api": {
        "default_store": "swift"
      },
      "images": [
        "cirros"
      ],
      "image_upload": true
    }


Cloud Files
-----------
    "glance": {
      "api": {
        "default_store": "swift",
        "swift_store_user": "<Cloud Files Tenant ID>:<Rackspace Cloud Files Username>",
        "swift_store_key": "<Rackspace Cloud Password>",
        "swift_store_auth_version": "2",
        "swift_store_auth_address": "https://identity.api.rackspacecloud.com/v2.0"
      },
      "images": [
        "cirros"
      ],
      "image_upload": true
    }

To obtain your Cloud Files Tenant ID use the following:
curl -s -X POST https://identity.api.rackspacecloud.com/v2.0/tokens -d '{"auth": {"passwordCredentials": {"username": "<Rackspace Cloud User Name>", "password": "<Rackspace Cloud Password"}}}' -H "Content-type: application/json" | python -mjson.tool | grep "tenantId.*Mosso" | head -1


Requirements
============

Chef 0.10.0 or higher required (for Chef environment use)

Platform
--------

* CentOS >= 6.3
* Ubuntu >= 12.04

Cookbooks
---------

The following cookbooks are dependencies:

* database
* dsh
* keystone
* monitoring
* mysql
* openssl
* osops-utils

Resources/Providers
===================

None


Recipes
=======

default
-------
- Includes recipes `api`, `registry`  

setup
-----
- Handles keystone registration and glance database creation

api
------
- Installs the glance-api server

registry
--------
- Installs the glance-registry server  

glance-rsyslog
--------------
- rsyslog glance configuration, automatically included in `setup`, `api`, and `registry`

replicator
----------
- drops in cron jobs to sync glance images when running 2 node HA setup w/ file storage

Data Bags
=========

None


Attributes 
==========

* `glance["services"]["api"]["scheme"]` - http or https
* `glance["services"]["api"]["network"]` - Network name to place service on
* `glance["services"]["api"]["port"]` - registry port
* `glance["services"]["api"]["path"]` - URI to use when using glance api
* `glance["services"]["registry"]["scheme"]` - http or https
* `glance["services"]["registry"]["network"]` - Network name to place service on
* `glance["services"]["registry"]["port"]` - registry port
* `glance["services"]["registry"]["path"]` - URI to use when using glance registry
* `glance["db"]["name"]` - Name of glance database
* `glance["db"]["user"]` - Username for glance database access
* `glance["service_tenant_name"]` - Tenant name used by glance when interacting with keystone - used in the API and registry paste.ini files
* `glance["service_user"]` - User name used by glance when interacting with keystone - used in the API and registry paste.ini files
* `glance["service_role"]` - User role used by glance when interacting with keystone - used in the API and registry paste.ini files
* `glance["api"]["default_store"]` - Toggles the backend storage type.  Currently supported is "file" and "swift", defaults to "file"
* `glance["api"]["swift"]["store_container"]` - Set the container used by glance to store images and snapshots.  Defaults to "glance"
* `glance["api"]["swift"]["store_large_object_size"]` - Set the size at which glance starts to chunnk files.  Defaults to "200" MB
* `glance["api"]["swift"]["store_large_object_chunk_size"]` - Set the chunk size for glance.  Defaults to "200" MB
* `glance["api"]["cache"]["image_cache_max_size"]` - Set the maximum size of image cache.  Defaults to "10" GB
* `glance["api"]["notifier_strategy"]` - Toggles the notifier strategy.  Currently supported are "noop", "rabbit", "qpid", and "logging", defaults to "noop"
* `glance["image_upload"]` - Toggles whether to automatically upload images in the `glance["images"]` array
* `glance["images"]` - Default list of images to upload to the glance repository as part of the install
* `glance["image]["<imagename>"]` - URL location of the <imagename> image. There can be multiple instances of this line to define multiple images (eg natty, maverick, fedora17 etc)
--- example `glance["image]["natty"]` - "http://c250663.r63.cf1.rackcdn.com/ubuntu-11.04-server-uec-amd64-multinic.tar.gz"
* `glance["syslog"]["use"]`
* `glance["syslog"]["facility"]`
* `glance["syslog"]["config_facility"]`
* `glance["replicator"]["interval"]` - Define how frequently replicator cron job should run
* `glance["platform"]` - Hash of platform specific package/service names and options

Templates
=========

* `22-glance.conf.erb` - rsyslog config file for glance
* `glance-api-paste.ini.erb` - Paste config for glance-api middleware
* `glance-api.conf.erb` - Config file for glance-api server
* `glance-cache-paste.ini.erb` - Paste config for glance-cache middleware
* `glance-cache.conf.erb` - Config file for glance image cache service
* `glance-image-sync.conf.erb` - Config for glance-image-sync cron
* `glance-logging.conf.erb` - Logging config for glance services
* `glance-registry-paste.ini.erb` - Paste config for glance-registry middleware
* `glance-registry.conf.erb` - Config file for glance-registry server
* `glance-scrubber-paste.ini.erb` - Paste config for glance-scrubber middleware
* `glance-scrubber.conf.erb` - Config file for glance image scrubber service
* `policy.json.erb` - Configuration of ACLs for glance API server


License and Author
==================

Author:: Justin Shepherd (<justin.shepherd@rackspace.com>)  
Author:: Jason Cannavale (<jason.cannavale@rackspace.com>)  
Author:: Ron Pedde (<ron.pedde@rackspace.com>)  
Author:: Joseph Breu (<joseph.breu@rackspace.com>)  
Author:: William Kelly (<william.kelly@rackspace.com>)  
Author:: Darren Birkett (<darren.birkett@rackspace.co.uk>)  
Author:: Evan Callicoat (<evan.callicoat@rackspace.com>)  
Author:: Matt Thompson (<matt.thompson@rackspace.co.uk>)  

Copyright 2012, Rackspace US, Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
