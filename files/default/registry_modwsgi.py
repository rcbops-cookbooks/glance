from glance.common import config
from glance.openstack.common import log as logging
from paste import deploy

config_files = ['/etc/glance/glance-registry-paste.ini', '/etc/glance/glance-registry.conf']
config.parse_args(default_config_files=config_files)
logging.setup('glance')

conf = '/etc/glance/glance-registry-paste.ini'
name = "glance-registry-keystone"

application = deploy.loadapp('config:%s' % conf, name=name)
